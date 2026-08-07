"""Image pipeline package (Milestone 11)."""

__version__ = "0.1.0-milestone11"
SERVICE_NAME = "image-pipeline"
OTEL_COLLECTOR_ENDPOINT = "http://otel-collector.rube-goldberg:4317"


def banner() -> str:
    return f"{SERVICE_NAME} {__version__}"


def init_telemetry():
    try:
        from opentelemetry import trace
        from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
        from opentelemetry.sdk.resources import Resource
        from opentelemetry.sdk.trace import TracerProvider
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.semconv.resource import ResourceAttributes

        resource = Resource.create({ResourceAttributes.SERVICE_NAME: SERVICE_NAME})
        provider = TracerProvider(resource=resource)
        exporter = OTLPSpanExporter(endpoint=OTEL_COLLECTOR_ENDPOINT, insecure=True)
        provider.add_span_processor(BatchSpanProcessor(exporter))
        trace.set_tracer_provider(provider)
    except ImportError:
        pass
