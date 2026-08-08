"""Image pipeline package (Milestone 11)."""

__version__ = "0.1.0-milestone11"
SERVICE_NAME = "image-pipeline"
OTEL_COLLECTOR_ENDPOINT = "http://otel-collector.rube-goldberg:4317"

_resource_cache: object | None = None


def _resource():
    global _resource_cache
    if _resource_cache is None:
        try:
            from opentelemetry.sdk.resources import Resource
            from opentelemetry.semconv.resource import ResourceAttributes

            _resource_cache = Resource.create({ResourceAttributes.SERVICE_NAME: SERVICE_NAME})
        except ImportError:
            _resource_cache = None
    return _resource_cache


def banner() -> str:
    return f"{SERVICE_NAME} {__version__}"


def init_telemetry():
    resource = _resource()

    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor

        provider = TracerProvider(resource=resource)
        exporter = OTLPSpanExporter(endpoint=OTEL_COLLECTOR_ENDPOINT, insecure=True)
        provider.add_span_processor(BatchSpanProcessor(exporter))
        trace.set_tracer_provider(provider)
    except ImportError:
        pass

    try:
        from opentelemetry import metrics
        from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
        from opentelemetry.sdk.metrics import MeterProvider
        from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader

        metric_exporter = OTLPMetricExporter(endpoint=OTEL_COLLECTOR_ENDPOINT, insecure=True)
        reader = PeriodicExportingMetricReader(metric_exporter)
        metrics.set_meter_provider(MeterProvider(resource=resource, readers=[reader]))
    except ImportError:
        pass

    try:
        from opentelemetry import logs
        from opentelemetry.exporter.otlp.proto.grpc._log_exporter import OTLPLogExporter
        from opentelemetry.sdk._logs import LoggerProvider, LoggingHandler
        from opentelemetry.sdk._logs.export import BatchLogRecordProcessor

        logger_provider = LoggerProvider(resource=resource)
        log_exporter = OTLPLogExporter(endpoint=OTEL_COLLECTOR_ENDPOINT, insecure=True)
        logger_provider.add_log_record_processor(BatchLogRecordProcessor(log_exporter))
        logs.set_logger_provider(logger_provider)
        handler = LoggingHandler(level=0, logger_provider=logger_provider)
        import logging

        logging.getLogger().addHandler(handler)
        logging.getLogger(SERVICE_NAME).addHandler(handler)
    except ImportError:
        pass
