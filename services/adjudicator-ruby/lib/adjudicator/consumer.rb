# frozen_string_literal: true

require 'kafka'
require 'json'
require '/app/lib/adjudicator'

module AdjudicatorConsumer
  KAFKA_BOOTSTRAP = ENV.fetch('KAFKA_BOOTSTRAP', 'kafka.rube-goldberg.svc.cluster.local:9092')
  KAFKA_GROUP_ID = ENV.fetch('KAFKA_GROUP_ID', 'adjudicator-v1')
  OBSERVATIONS_TOPIC = ENV.fetch('OBSERVATIONS_TOPIC', 'rg.ocr-observations.v1')
  ADJUDICATED_TOPIC = ENV.fetch('ADJUDICATED_TOPIC', 'rg.symbols-adjudicated.v1')
  QUALITY_RETRY_TOPIC = ENV.fetch('QUALITY_RETRY_TOPIC', 'rg.quality-retry.v1')

  module_function

  def run
    kafka = Kafka.new([KAFKA_BOOTSTRAP], client_id: Adjudicator::SERVICE_NAME)
    consumer = kafka.consumer(group_id: KAFKA_GROUP_ID)

    consumer.subscribe(OBSERVATIONS_TOPIC)

    puts "Consuming #{OBSERVATIONS_TOPIC} -> #{ADJUDICATED_TOPIC}"

    consumer.each_message do |message|
      process_message(kafka, message)
    end
  end

  def process_message(kafka, message)
    event = JSON.parse(message.value)
    data = event['data'] || event

    validate_no_prohibited_fields(event)
    validate_maturity(data)

    observations = data['observations'] || {}
    layout = data.dig('observations', 'layout') || data['layout'] || []

    run_id = data['runId'] || 'unknown'
    step_id = data['stepId'] || 'unknown'
    attempt = data['attempt'] || 1

    result = Adjudicator::AdjudicatorImpl.adjudicate(
      observations,
      layout,
      run_id: run_id,
      step_id: step_id,
      attempt: attempt
    )

    publish_events(kafka, data, result)
  rescue JSON::ParserError => e
    warn "Failed to parse message: #{e.message}"
  rescue StandardError => e
    warn "Failed to process message: #{e.message}"
  end

  def validate_no_prohibited_fields(event)
    violations = Adjudicator.check_prohibited_fields(JSON.generate(event))
    raise "Prohibited fields detected: #{violations.join(', ')}" unless violations.empty?
  end

  def validate_maturity(data)
    input_maturity = data['inputMaturity'] || 0
    output_maturity = data['outputMaturity'] || 0
    return if input_maturity == 60 && output_maturity == 70

    raise "Invalid maturity: input=#{input_maturity}, output=#{output_maturity}"
  end

  def publish_events(kafka, data, result)
    run_id = data['runId'] || 'unknown'
    step_id = data['stepId'] || 'unknown'
    attempt = data['attempt'] || 1

    producer = kafka.producer

    result[:acceptedSymbols].each do |symbol|
      event = Adjudicator::AdjudicatorImpl.build_symbol_event(
        run_id, step_id, generate_glyph_instance_id(symbol[:position]), attempt, symbol[:position], symbol
      )
      producer.produce(event, topic: ADJUDICATED_TOPIC)
    end

    result[:retryEvents].each do |event|
      producer.produce(event, topic: QUALITY_RETRY_TOPIC)
    end

    producer.deliver_messages
  end

  def generate_glyph_instance_id(position)
    "glyph-#{position}"
  end
end
