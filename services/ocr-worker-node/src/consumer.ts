import { Kafka, logLevel, Producer } from 'kafkajs';
import { readFileSync, existsSync, mkdirSync, unlinkSync, renameSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, basename } from 'node:path';
import { spawnSync } from 'node:child_process';

import { createKafka, WorkerConfig } from './kafka.js';
import { createMinioClient, downloadToTemp, cleanupTemp, MinioConfig } from './minio.js';
import {
  ALLOWED_ALPHABET,
  OcrObservations,
  PreprocessReport,
  performOcr,
  buildOcrEvent,
  checkProhibitedFields,
  cryptoHash,
  banner,
} from './index.js';

const INPUT_TOPIC = process.env.OCR_INPUT_TOPIC ?? 'rg.ocr-images.v1';
const OUTPUT_TOPIC = process.env.OCR_OUTPUT_TOPIC ?? 'rg.ocr-observations.v1';

const kafkaConfig: WorkerConfig = {
  bootstrap: process.env.KAFKA_BOOTSTRAP ?? 'kafka.rube-goldberg.svc.cluster.local:9092',
  groupId: process.env.KAFKA_GROUP_ID ?? 'ocr-worker-v1',
  inputTopic: INPUT_TOPIC,
  outputTopic: OUTPUT_TOPIC,
};

const minioConfig: MinioConfig = {
  endpoint: process.env.MINIO_ENDPOINT ?? 'http://minio.rube-goldberg.svc.cluster.local:9000',
  accessKey: process.env.MINIO_ACCESS_KEY ?? '',
  secretKey: process.env.MINIO_SECRET_KEY ?? '',
  bucket: process.env.MINIO_BUCKET ?? 'rube-goldberg-artifacts',
};

function validateMaturity(event: Record<string, unknown>): void {
  const inputMaturity = (event.inputMaturity as number) ?? 0;
  const outputMaturity = (event.outputMaturity as number) ?? 0;
  if (inputMaturity !== 50 || outputMaturity !== 60) {
    throw new Error(`Invalid maturity: input=${inputMaturity}, output=${outputMaturity}`);
  }
}

function validateNoProhibited(event: Record<string, unknown>): void {
  const violations = checkProhibitedFields(JSON.stringify(event));
  if (violations.length > 0) {
    throw new Error(`Prohibited fields detected: ${violations.join(', ')}`);
  }
}

export async function runConsumer(): Promise<void> {
  console.log(banner());

  const kafka = createKafka(kafkaConfig);
  const consumer = kafka.consumer({ groupId: kafkaConfig.groupId });
  const producer = kafka.producer();
  const minio = createMinioClient(minioConfig);

  await consumer.connect();
  await producer.connect();
  await consumer.subscribe({ topic: kafkaConfig.inputTopic, fromBeginning: false });

  console.log(`Consuming ${kafkaConfig.inputTopic} -> ${kafkaConfig.outputTopic}`);

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) return;
      const event = JSON.parse(message.value.toString()) as Record<string, unknown>;
      const data = (event.data ?? event) as Record<string, unknown>;

      validateNoProhibited(event);
      validateMaturity(data);

      const runId = data.runId as string;
      const stepId = data.stepId as string;
      const attempt = (data.attempt as number) ?? 1;

      const ocrImage = data.ocrImage as Record<string, unknown> | undefined;
      const positionCrops = (data.positionCrops as Array<Record<string, unknown>>) ?? [];

      if (!ocrImage?.objectKey || !positionCrops.length) {
        console.warn(`Skipping event ${event.id ?? 'unknown'}: missing ocrImage or positionCrops`);
        return;
      }

      const cropsDir = join(tmpdir(), `ocr-crops-${runId}`);
      mkdirSync(cropsDir, { recursive: true });

      const tmpFiles: string[] = [];
      try {
        const phraseImagePath = await downloadToTemp(
          minio,
          minioConfig.bucket,
          ocrImage.objectKey as string,
        );
        tmpFiles.push(phraseImagePath);

        for (const crop of positionCrops) {
          const cropPath = join(cropsDir, `crop-position-${crop.position}.png`);
          const tmpPath = await downloadToTemp(minio, minioConfig.bucket, crop.objectKey as string);
          renameSync(tmpPath, cropPath);
          tmpFiles.push(cropPath);
        }

        const manifest: PreprocessReport = {
          layout: positionCrops.map((c) => ({
            position: c.position as number,
            x: (c.x as number) ?? 0,
            y: (c.y as number) ?? 0,
            width: (c.width as number) ?? 0,
            height: (c.height as number) ?? 0,
            advanceWidth: 1.0,
            baseline: 0.0,
          })),
          totalWidth: (ocrImage.width as number) ?? 0,
          totalHeight: (ocrImage.height as number) ?? 0,
        };

        const observations = performOcr(phraseImagePath, manifest, cropsDir);

        const inputHash = cryptoHash(JSON.stringify(data));
        const outputEvent = buildOcrEvent(
          runId,
          stepId,
          attempt,
          inputHash,
          observations,
          (data.inputArtifacts as string[]) ?? [],
          (data.outputArtifacts as string[]) ?? [],
        );

        validateNoProhibited(outputEvent);

        await producer.send({
          topic: kafkaConfig.outputTopic,
          messages: [{ value: JSON.stringify(outputEvent) }],
        });
      } finally {
        for (const f of tmpFiles) {
          cleanupTemp(f);
        }
      }
    },
  });
}

if (process.argv[1] && process.argv[1].endsWith('consumer.js')) {
  (async () => {
    while (true) {
      try {
        await runConsumer();
      } catch (err) {
        console.error('ocr-worker consumer error:', err);
        await new Promise((r) => setTimeout(r, 5000));
      }
    }
  })();
}
