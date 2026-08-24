# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require File.expand_path('../lib/adjudicator/consumer', __dir__)

class FakeAdjudicatorProducer
  attr_reader :events

  def initialize
    @events = {}
  end

  def produce(topic:, payload:)
    (@events[topic] ||= []) << JSON.parse(payload)
  end
end

class ConsumerArtifactTraceTest < Minitest::Test
  OBSERVATIONS = {
    'fullPhrase' => {
      'rawText' => 'H W',
      'confidence' => 95.2,
      'symbols' => [
        { 'text' => 'H', 'confidence' => 0.98, 'x' => 10, 'y' => 0, 'width' => 100,
          'height' => 100 },
        { 'text' => 'W', 'confidence' => 0.96, 'x' => 180, 'y' => 0, 'width' => 100,
          'height' => 100 }
      ]
    },
    'positionObservations' => [
      { 'position' => 0, 'candidate' => 'H', 'confidence' => 0.97, 'alternatives' => %w[H N] },
      { 'position' => 6, 'candidate' => 'W', 'confidence' => 0.95, 'alternatives' => %w[W M] }
    ],
    'spacingObservations' => [
      { 'betweenPositions' => [0, 6], 'pixelGap' => 80, 'medianGlyphGapRatio' => 0.8 },
      { 'betweenPositions' => [6, 9], 'pixelGap' => 250, 'medianGlyphGapRatio' => 3.5 }
    ]
  }.freeze

  LAYOUT = [
    { 'position' => 0, 'x' => 10, 'y' => 0, 'width' => 100, 'height' => 100,
      'advanceWidth' => 1.0, 'baseline' => 80 },
    { 'position' => 5, 'x' => 120, 'y' => 0, 'width' => 0, 'height' => 0,
      'advanceWidth' => 0.6, 'baseline' => 0 },
    { 'position' => 6, 'x' => 180, 'y' => 0, 'width' => 100, 'height' => 100,
      'advanceWidth' => 1.0, 'baseline' => 80 }
  ].freeze

  def build_observations_event
    {
      'specversion' => '1.0',
      'type' => 'rg.ocr-observations.v1',
      'data' => {
        'runId' => 'run-1',
        'stepId' => 'obs-step-1',
        'attempt' => 1,
        'inputMaturity' => 60,
        'outputMaturity' => 70,
        'inputArtifacts' => ['runs/run-1/composed.png'],
        'outputArtifacts' => ['runs/run-1/ocr.png'],
        'observations' => OBSERVATIONS,
        'layout' => LAYOUT
      }
    }
  end

  def test_emitted_events_trace_consumed_outputs_and_claim_no_outputs
    producer = FakeAdjudicatorProducer.new
    message = Struct.new(:payload).new(JSON.generate(build_observations_event))

    AdjudicatorConsumer.process_message(producer, message)

    adjudicated = producer.events[AdjudicatorConsumer::ADJUDICATED_TOPIC] || []
    refute_empty(adjudicated)

    # Chain rule: inputs trace the consumed observations event's outputs; the
    # adjudicator writes no artifacts of its own.
    adjudicated.each do |event|
      data = event['data']
      assert_equal(['runs/run-1/ocr.png'], data['inputArtifacts'])
      assert_empty(data['outputArtifacts'])
    end

    # Both publish loops ran: at least one accepted symbol and one gap.
    types = adjudicated.map { |event| event['data']['symbol']['tokenType'] }
    assert_includes(types, 'SYMBOL')
    assert_includes(types, 'GAP')
  end
end
