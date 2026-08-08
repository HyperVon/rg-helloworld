# frozen_string_literal: true

require 'opentelemetry/sdk'
require 'opentelemetry/exporter/otlp'
require 'opentelemetry-logs-sdk'
require 'opentelemetry-exporter-otlp-logs'
require 'opentelemetry/instrumentation/all'

module Rghello
  module Telemetry
    OTEL_ENDPOINT = ENV.fetch('OTEL_EXPORTER_OTLP_ENDPOINT', 'http://otel-collector.rube-goldberg:4317')
    SERVICE_NAME = File.basename(File.expand_path('../..', __dir__))

    @configured = false

    class << self
      attr_reader :configured

      def configure
        return if @configured

        @configured = true

        trace_exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: OTEL_ENDPOINT)
        span_processor = OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(trace_exporter)

        log_exporter = OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(endpoint: OTEL_ENDPOINT)
        log_processor = OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(log_exporter)

        OpenTelemetry::SDK.configure do |c|
          c.service_name = SERVICE_NAME
          c.add_span_processor(span_processor)
          c.add_log_record_processor(log_processor)
          c.use_all
        end

        at_exit { shutdown }

        OpenTelemetry.logger.info { "Telemetry initialized for service: #{SERVICE_NAME}" }
      rescue StandardError => e
        warn "Telemetry setup failed (continuing without): #{e.class}: #{e.message}"
        @configured = false
      end

      def shutdown
        begin
          OpenTelemetry.tracer_provider&.shutdown
        rescue StandardError => e
          warn "Tracer provider shutdown error: #{e.message}"
        end
        begin
          OpenTelemetry.logger_provider&.shutdown
        rescue StandardError => e
          warn "Logger provider shutdown error: #{e.message}"
        end
      end
    end
  end
end
