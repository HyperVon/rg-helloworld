import { logs, SeverityNumber } from '@opentelemetry/api-logs';

const OTEL_ENDPOINT_DEFAULT = 'http://otel-collector.rube-goldberg:4317';

type NodeProc = {
  versions: { node: string };
  on: (event: string, listener: (...args: unknown[]) => void) => void;
  exit: (code?: number) => void;
  env: Record<string, string | undefined>;
};

function nodeProcess(): NodeProc | undefined {
  return (globalThis as unknown as { process?: NodeProc }).process;
}

function isNodeRuntime(): boolean {
  const proc = nodeProcess();
  return proc != null && typeof proc.versions?.node === 'string' && typeof proc.on === 'function';
}

function otel(name: string): string {
  return `@opentelemetry/${name}`;
}

let initialized = false;

export async function initTelemetry(
  serviceName: string,
  serviceVersion?: string,
): Promise<boolean> {
  if (initialized) return false;
  initialized = true;

  if (!isNodeRuntime()) {
    console.log(
      `[${serviceName}] ${serviceVersion ? `${serviceVersion} ` : ''}startup: telemetry disabled (non-Node runtime)`,
    );
    return false;
  }

  const proc = nodeProcess()!;

  try {
    const endpoint = (proc.env.OTEL_EXPORTER_OTLP_ENDPOINT || OTEL_ENDPOINT_DEFAULT).trim();

    const { NodeSDK } = (await import(otel('sdk-node'))) as typeof import('@opentelemetry/sdk-node');
    const { SimpleLogRecordProcessor } = (await import(otel('sdk-logs'))) as typeof import('@opentelemetry/sdk-logs');
    const { OTLPTraceExporter } = (await import(otel('exporter-trace-otlp-grpc'))) as typeof import('@opentelemetry/exporter-trace-otlp-grpc');
    const { OTLPLogExporter } = (await import(otel('exporter-logs-otlp-grpc'))) as typeof import('@opentelemetry/exporter-logs-otlp-grpc');
    const { getNodeAutoInstrumentations } = (await import(otel('auto-instrumentations-node'))) as typeof import('@opentelemetry/auto-instrumentations-node');

    const sdk = new NodeSDK({
      serviceName,
      traceExporter: new OTLPTraceExporter({ url: endpoint }),
      logRecordProcessors: [
        new SimpleLogRecordProcessor({ exporter: new OTLPLogExporter({ url: endpoint }) }),
      ],
      instrumentations: [getNodeAutoInstrumentations()],
    });

    sdk.start();

    logs.getLogger('rghw').emit({
      severityNumber: SeverityNumber.INFO,
      body: 'service started',
      attributes: {
        'service.name': serviceName,
        ...(serviceVersion ? { 'service.version': serviceVersion } : {}),
      },
    });

    const shutdown = async () => {
      try {
        await sdk.shutdown();
      } catch {
        // best-effort flush of telemetry on exit
      }
      proc.exit(0);
    };
    proc.on('SIGTERM', shutdown);
    proc.on('SIGINT', shutdown);

    return true;
  } catch (err) {
    const detail = err instanceof Error ? err.message : String(err);
    console.warn(`[${serviceName}] telemetry unavailable, running without OTLP export: ${detail}`);
    return false;
  }
}
