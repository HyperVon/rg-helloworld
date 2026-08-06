# frozen_string_literal: true

require 'minitest/autorun'
require 'adjudicator'
require 'tmpdir'
require 'fileutils'
require 'json'

class AdjudicatorLogicTest < Minitest::Test
  SAMPLE_LAYOUT = [
    { 'position' => 0, 'x' => 10, 'y' => 0, 'width' => 100, 'height' => 100, 'advanceWidth' => 1.0,
      'baseline' => 80 },
    { 'position' => 5, 'x' => 120, 'y' => 0, 'width' => 0, 'height' => 0, 'advanceWidth' => 0.6,
      'baseline' => 0 },
    { 'position' => 6, 'x' => 180, 'y' => 0, 'width' => 100, 'height' => 100,
      'advanceWidth' => 1.0, 'baseline' => 80 }
  ].freeze

  SAMPLE_OBSERVATIONS = {
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
      { 'betweenPositions' => [6, 9], 'pixelGap' => 20, 'medianGlyphGapRatio' => 0.2 }
    ]
  }.freeze

  def test_adjudicate_accepts_symbols_with_agreement
    result = Adjudicator::AdjudicatorImpl.adjudicate(SAMPLE_OBSERVATIONS, SAMPLE_LAYOUT,
                                                     run_id: 'run-1', step_id: 'step-1', attempt: 1)
    assert(result[:allAccepted])
    assert_empty(result[:retryEvents])
    assert_equal(2, result[:acceptedSymbols].length)
    symbol = result[:acceptedSymbols].first
    assert_equal('H', symbol[:utf8])
    assert_equal(0, symbol[:position])
    assert_equal('SYMBOL', symbol[:tokenType])
    assert(symbol[:evidence][:agreement])
  end

  def test_adjudicate_detects_gaps_from_spacing
    observations = {
      'fullPhrase' => { 'rawText' => 'H W', 'confidence' => 95.2,
                        'symbols' => [
                          { 'text' => 'H', 'confidence' => 0.98, 'x' => 10, 'y' => 0, 'width' => 100,
                            'height' => 100 },
                          { 'text' => 'W', 'confidence' => 0.96, 'x' => 180, 'y' => 0, 'width' => 100,
                            'height' => 100 }
                        ] },
      'positionObservations' => [
        { 'position' => 0, 'candidate' => 'H', 'confidence' => 0.97, 'alternatives' => %w[H N] },
        { 'position' => 6, 'candidate' => 'W', 'confidence' => 0.95, 'alternatives' => %w[W M] }
      ],
      'spacingObservations' => [
        { 'betweenPositions' => [0, 6], 'pixelGap' => 80, 'medianGlyphGapRatio' => 0.8 },
        { 'betweenPositions' => [6, 9], 'pixelGap' => 20, 'medianGlyphGapRatio' => 0.2 },
        { 'betweenPositions' => [9, 12], 'pixelGap' => 250, 'medianGlyphGapRatio' => 3.5 }
      ]
    }
    result = Adjudicator::AdjudicatorImpl.adjudicate(observations, SAMPLE_LAYOUT,
                                                     run_id: 'run-1', step_id: 'step-1', attempt: 1)
    assert_equal(1, result[:gaps].length)
    gap = result[:gaps].first
    assert_equal('GAP', gap[:tokenType])
    assert_equal(9, gap[:position])
  end

  def test_adjudicate_triggers_retry_on_ambiguous
    observations = {
      'fullPhrase' => { 'rawText' => 'H W', 'confidence' => 95.2,
                        'symbols' => [{ 'text' => 'H', 'confidence' => 0.40, 'x' => 10, 'y' => 0,
                                        'width' => 100, 'height' => 100 }] },
      'positionObservations' => [
        { 'position' => 0, 'candidate' => 'H', 'confidence' => 0.35, 'alternatives' => %w[B N] }
      ],
      'spacingObservations' => []
    }
    result = Adjudicator::AdjudicatorImpl.adjudicate(observations, SAMPLE_LAYOUT,
                                                     run_id: 'run-1', step_id: 'step-1', attempt: 1)
    refute(result[:allAccepted])
    assert_equal(1, result[:retryEvents].length)
    assert_equal('ambiguous', result[:retryEvents].first[:data][:reason])
  end

  def test_adjudicate_rejects_prohibited_fields
    observations = {
      'fullPhrase' => { 'rawText' => 'X', 'confidence' => 95.0, 'symbols' => [] },
      'positionObservations' => [],
      'spacingObservations' => []
    }
    assert_raises(RuntimeError) do
      Adjudicator::AdjudicatorImpl.adjudicate(
        { 'targetText' => 'H' }.merge(observations),
        SAMPLE_LAYOUT, run_id: 'run-1', step_id: 'step-1', attempt: 1
      )
    end
  end

  def test_check_prohibited_fields_clean
    clean = '{"specversion":"1.0","data":{"runId":"r"}}'
    assert_empty(Adjudicator::AdjudicatorImpl.check_prohibited_fields(clean))
  end

  def test_check_prohibited_fields_detects_all
    %w[targetText expectedCharacter unicodeCodePoint characterName glyphLabel].each do |field|
      poisoned = "{\"#{field}\":\"value\"}"
      violations = Adjudicator::AdjudicatorImpl.check_prohibited_fields(poisoned)
      assert_includes(violations, field)
    end
  end

  def test_build_symbol_event_has_correct_maturity
    event = Adjudicator::AdjudicatorImpl.build_symbol_event(
      'run-1', 'step-1', 'glyph-1', 1, 0,
      { position: 0, tokenType: 'SYMBOL', utf8: 'H', confidence: 0.96, evidence: { agreement: true } }
    )
    assert_equal('rg.symbols-adjudicated.v1', event[:type])
    assert_equal(70, event[:data][:inputMaturity])
    assert_equal(80, event[:data][:outputMaturity])
    assert_equal('adjudicate-symbol', event[:data][:transformation][:name])
  end

  def test_build_quality_retry_event_structure
    event = Adjudicator::AdjudicatorImpl.build_quality_retry_event(
      'run-1', 'step-1', 2, 0, 'ambiguous'
    )
    assert_equal('rg.quality-retry.v1', event[:type])
    assert_equal(70, event[:data][:inputMaturity])
    assert_equal(70, event[:data][:outputMaturity])
    assert_equal('run-1', event[:correlationid])
  end

  def test_calculate_median
    impl = Adjudicator::AdjudicatorImpl
    assert_equal(5.0, impl.send(:calculate_median, [1, 3, 5, 7, 9]))
    assert_equal(4.0, impl.send(:calculate_median, [1, 3, 5, 7]))
    assert_equal(0, impl.send(:calculate_median, []))
  end

  def test_find_full_phrase_symbol
    impl = Adjudicator::AdjudicatorImpl
    symbols = [{ 'text' => 'H', 'confidence' => 0.98, 'x' => 10 }]
    entry = { 'position' => 0, 'x' => 10 }
    result = impl.send(:find_full_phrase_symbol, symbols, entry)
    assert_equal('H', result['text'])
  end

  def test_find_full_phrase_symbol_returns_nil_when_not_found
    impl = Adjudicator::AdjudicatorImpl
    result = impl.send(:find_full_phrase_symbol, [], { 'position' => 0 })
    assert_nil(result)
  end

  def test_run_once_writes_output
    Dir.mktmpdir do |dir|
      input_path = File.join(dir, 'observations.json')
      layout_path = File.join(dir, 'layout.json')
      output_path = File.join(dir, 'result.json')

      File.write(input_path, SAMPLE_OBSERVATIONS.to_json)
      File.write(layout_path, { 'layout' => SAMPLE_LAYOUT }.to_json)

      result = Adjudicator::AdjudicatorImpl.run_once(
        input_path, layout_path,
        output_path: output_path
      )

      assert(result[:allAccepted])
      assert(File.exist?(output_path))
      saved = JSON.parse(File.read(output_path))
      assert_equal(result[:acceptedSymbols].length, saved['acceptedSymbols'].length)
      assert_equal(result[:gaps].length, saved['gaps'].length)
    end
  end

  def test_high_confidence_symbol_accepted_without_agreement
    observations = {
      'fullPhrase' => { 'rawText' => 'A B', 'confidence' => 90.0, 'symbols' => [
        { 'text' => 'A', 'confidence' => 0.88, 'x' => 10, 'y' => 0, 'width' => 100, 'height' => 100 }
      ] },
      'positionObservations' => [
        { 'position' => 0, 'candidate' => 'A', 'confidence' => 0.95, 'alternatives' => ['A'] }
      ],
      'spacingObservations' => []
    }
    result = Adjudicator::AdjudicatorImpl.adjudicate(observations, SAMPLE_LAYOUT,
                                                     run_id: 'run-1', step_id: 'step-1', attempt: 1)
    assert_equal(1, result[:acceptedSymbols].length)
    assert_equal('A', result[:acceptedSymbols].first[:utf8])
  end

  def test_adjudicate_respects_minimum_confidence
    assert_equal(0.6, Adjudicator::MIN_CONFIDENCE)
    assert_equal(0.85, Adjudicator::HIGH_CONFIDENCE)
  end

  private

  def deep_symbolize_keys(obj)
    case obj
    when Hash
      obj.transform_keys(&:to_sym).transform_values { |v| deep_symbolize_keys(v) }
    when Array
      obj.map { |v| deep_symbolize_keys(v) }
    else
      obj
    end
  end
end
