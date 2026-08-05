import { Kafka, type Consumer, type Producer } from 'kafkajs';

export const SERVICE_NAME = 'temp-worker';
export const SERVICE_VERSION = '0.1.0-milestone3';

export const DEFAULT_KAFKA_BROKER = 'localhost:9092';
export const PLANNING_TOPIC = 'rg.glyph-blueprints.v1';
export const TEMP_ECHO_TOPIC = 'rg.temp-echo.v1';

export interface WorkerConfig {
  brokers: string[];
  planningTopic: string;
  echoTopic: string;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): WorkerConfig {
  return {
    brokers: [env.KAFKA_BOOTSTRAP_SERVERS ?? DEFAULT_KAFKA_BROKER],
    planningTopic: env.PLANNING_TOPIC ?? PLANNING_TOPIC,
    echoTopic: env.TEMP_ECHO_TOPIC ?? TEMP_ECHO_TOPIC,
  };
}

export interface BlueprintMessage {
  specversion: string;
  id: string;
  source: string;
  type: string;
  subject?: string;
  correlationid?: string;
  data: Record<string, string>;
}

export function parseBlueprint(raw: string): BlueprintMessage {
  return JSON.parse(raw) as BlueprintMessage;
}

export function buildEchoEvent(blueprint: BlueprintMessage): Record<string, unknown> {
  return {
    specversion: '1.0',
    id: crypto.randomUUID(),
    source: 'temp-worker',
    type: TEMP_ECHO_TOPIC,
    subject: blueprint.subject,
    datacontenttype: 'application/json',
    correlationid: blueprint.correlationid ?? blueprint.data.runId,
    data: {
      assembledText: blueprint.data.message,
    },
  };
}

export function echoFromMessage(raw: string | null): { runId: string; event: string } | null {
  if (raw === null) {
    return null;
  }
  const blueprint = parseBlueprint(raw);
  const runId = blueprint.correlationid ?? blueprint.data.runId;
  if (runId === undefined) {
    return null;
  }
  return { runId, event: JSON.stringify(buildEchoEvent(blueprint)) };
}

export function banner(): string {
  return `${SERVICE_NAME} ${SERVICE_VERSION} (temporary, removed in Milestone 4)`;
}

export type KafkaFactory = (config: WorkerConfig) => Kafka;

export function main(
  kafkaFactory: KafkaFactory = (config) =>
    new Kafka({ clientId: SERVICE_NAME, brokers: config.brokers }),
): void {
  const config = configFromEnv();
  runWorker(config, kafkaFactory(config)).catch((error: unknown) => {
    console.error('fatal error starting temp worker:', error);
    process.exit(1);
  });
}

if (process.argv[1] !== undefined && import.meta.url === new URL(process.argv[1], 'file:').href) {
  main();
}

export async function startWorker(config: WorkerConfig, kafka: Kafka): Promise<void> {
  const producer: Producer = kafka.producer();
  const consumer: Consumer = kafka.consumer({ groupId: 'temp-worker-node' });

  await producer.connect();
  await consumer.connect();
  await consumer.subscribe({ topic: config.planningTopic, fromBeginning: false });
  await consumer.run({
    eachMessage: async ({ message }) => {
      const echo = echoFromMessage(message.value?.toString() ?? null);
      if (echo !== null) {
        await producer.send({
          topic: config.echoTopic,
          messages: [{ key: echo.runId, value: echo.event }],
        });
      }
    },
  });
}

export async function runWorker(config: WorkerConfig, kafka: Kafka): Promise<void> {
  await startWorker(config, kafka);
  await new Promise<void>(() => {});
}
