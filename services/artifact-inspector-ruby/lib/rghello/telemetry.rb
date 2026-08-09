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
        configure_sdk

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

      private

      def configure_sdk
        OpenTelemetry::SDK.configure do |config|
          config.service_name = SERVICE_NAME
          config.add_span_processor(build_span_processor)
          config.add_log_record_processor(build_log_processor)
          config.use_all
        end
      end

      def build_span_processor
        exporter = OpenTelemetry::Exporter::OTLP::Exporter.new(endpoint: OTEL_ENDPOINT)
        OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor.new(exporter)
      end

      def build_log_processor
        exporter = OpenTelemetry::Exporter::OTLP::Logs::LogsExporter.new(endpoint: OTEL_ENDPOINT)
        OpenTelemetry::SDK::Logs::Export::BatchLogRecordProcessor.new(exporter)
      end
    end
  end
end
