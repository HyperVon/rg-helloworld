from __future__ import annotations

import asyncio
import contextlib
import json
import os
from typing import Any

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

KAFKA_BOOTSTRAP = os.environ.get(
    "KAFKA_BOOTSTRAP_SERVERS", "kafka.rube-goldberg.svc.cluster.local:9092"
)
GROUP_ID = os.environ.get("KAFKA_CONSUMER_GROUP", "image-pipeline-v1")


async def create_consumer(topics: list[str], group_id: str = GROUP_ID) -> AIOKafkaConsumer:
    last_err: Exception | None = None
    for attempt in range(30):
        consumer = AIOKafkaConsumer(
            *topics,
            bootstrap_servers=KAFKA_BOOTSTRAP,
            group_id=group_id,
            auto_offset_reset="earliest",
            enable_auto_commit=True,
            value_deserializer=lambda v: json.loads(v.decode("utf-8")),
        )
        try:
            await consumer.start()
            if attempt > 0:
                print(f"[kafka-consumer] connected on attempt {attempt + 1}", flush=True)
            return consumer
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"[kafka-consumer] attempt {attempt + 1}/30 failed: {e} — retrying in 2s", flush=True)
            with contextlib.suppress(Exception):
                await consumer.stop()
            await asyncio.sleep(2)
    raise last_err or RuntimeError("kafka consumer failed")


async def create_producer() -> AIOKafkaProducer:
    last_err: Exception | None = None
    for attempt in range(30):
        producer = AIOKafkaProducer(
            bootstrap_servers=KAFKA_BOOTSTRAP,
            value_serializer=lambda v: json.dumps(v, sort_keys=True).encode("utf-8"),
        )
        try:
            await producer.start()
            if attempt > 0:
                print(f"[kafka-producer] connected on attempt {attempt + 1}", flush=True)
            return producer
        except Exception as e:  # noqa: BLE001
            last_err = e
            print(f"[kafka-producer] attempt {attempt + 1}/30 failed: {e} — retrying in 2s", flush=True)
            with contextlib.suppress(Exception):
                await producer.stop()
            await asyncio.sleep(2)
    raise last_err or RuntimeError("kafka producer failed")


async def publish(producer: AIOKafkaProducer, topic: str, event: dict[str, Any]) -> None:
    await producer.send_and_wait(topic, event)


async def consume(consumer: AIOKafkaConsumer, timeout_ms: int = 1000):
    msg = await consumer.getone()
    return msg
