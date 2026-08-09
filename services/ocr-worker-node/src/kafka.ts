import { createRequire } from 'node:module';
import { Kafka, logLevel } from 'kafkajs';

const require = createRequire(import.meta.url);
const RequestQueue = require('kafkajs/src/network/requestQueue');

const CHECK_PENDING_REQUESTS_INTERVAL = 10;

const originalScheduleCheckPendingRequests = RequestQueue.prototype.scheduleCheckPendingRequests;
RequestQueue.prototype.scheduleCheckPendingRequests =
  function patchedScheduleCheckPendingRequests() {
    let scheduleAt = this.throttledUntil - Date.now();
    if (scheduleAt < 0) {
      scheduleAt = this.pending.length > 0 ? CHECK_PENDING_REQUESTS_INTERVAL : 0;
    }
    if (!this.throttleCheckTimeoutId) {
      if (this.pending.length > 0) {
        scheduleAt = scheduleAt > 0 ? scheduleAt : CHECK_PENDING_REQUESTS_INTERVAL;
      }
      this.throttleCheckTimeoutId = setTimeout(() => {
        this.throttleCheckTimeoutId = null;
        this.checkPendingRequests();
      }, scheduleAt);
    }
  };

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
    retry: {
      retries: 20,
      initialRetryTime: 5000,
      maxRetryTime: 30000,
      factor: 0.2,
      multiplier: 2,
    },
  });
}
