import { Kafka, logLevel } from 'kafkajs';

export interface WorkerConfig {
  bootstrap: string;
  groupId: string;
  inputTopic: string;
  outputTopic: string;
}

export function createKafka(config: WorkerConfig): Kafka {
  return new Kafka({
    brokers: [config.bootstrap],
    logLevel: logLevel.WARN,
    connectionTimeout: 5000,
    requestTimeout: 30000,
  });
}
