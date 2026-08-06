import { Client } from 'minio';
import { readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export interface MinioConfig {
  endpoint: string;
  accessKey: string;
  secretKey: string;
  bucket: string;
}

export function createMinioClient(config: MinioConfig): Client {
  return new Client({
    endPoint: config.endpoint.replace(/^https?:\/\//, '').replace(/:\d+$/, ''),
    port: parseInt(config.endpoint.split(':')[2] ?? '9000', 10),
    useSSL: config.endpoint.startsWith('https'),
    accessKey: config.accessKey,
    secretKey: config.secretKey,
  });
}

export async function downloadToTemp(
  client: Client,
  bucket: string,
  objectKey: string,
): Promise<string> {
  const tmpPath = join(tmpdir(), `${Date.now()}-${objectKey.replace(/\//g, '_')}`);
  const stream = await client.getObject(bucket, objectKey);
  const chunks: Buffer[] = [];
  await new Promise<void>((resolve, reject) => {
    stream.on('data', (chunk: Buffer) => chunks.push(chunk));
    stream.on('end', () => resolve());
    stream.on('error', reject);
  });
  writeFileSync(tmpPath, Buffer.concat(chunks));
  return tmpPath;
}

export function cleanupTemp(path: string): void {
  try {
    unlinkSync(path);
  } catch {
    // ignore cleanup errors
  }
}
