from __future__ import annotations

import json
import os
from typing import Any

from aiokafka import AIOKafkaConsumer, AIOKafkaProducer

KAFKA_BOOTSTRAP = os.environ.get(
    "KAFKA_BOOTSTRAP_SERVERS", "kafka.rube-goldberg.svc.cluster.local:9092"
)
GROUP_ID = os.environ.get("KAFKA_CONSUMER_GROUP", "image-pipeline-v1")


async def create_consumer(topics: list[str], group_id: str = GROUP_ID) -> AIOKafkaConsumer:
    consumer = AIOKafkaConsumer(
        *topics,
        bootstrap_servers=KAFKA_BOOTSTRAP,
        group_id=group_id,
        auto_offset_reset="earliest",
        enable_auto_commit=True,
        value_deserializer=lambda v: json.loads(v.decode("utf-8")),
    )
    await consumer.start()
    return consumer


async def create_producer() -> AIOKafkaProducer:
    producer = AIOKafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP,
        value_serializer=lambda v: json.dumps(v, sort_keys=True).encode("utf-8"),
    )
    await producer.start()
    return producer


async def publish(producer: AIOKafkaProducer, topic: str, event: dict[str, Any]) -> None:
    await producer.send_and_wait(topic, event)


async def consume(consumer: AIOKafkaConsumer, timeout_ms: int = 1000):
    msg = await consumer.getone()
    return msg
