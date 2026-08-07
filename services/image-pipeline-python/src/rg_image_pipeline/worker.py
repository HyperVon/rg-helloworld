from __future__ import annotations

import asyncio
import json
import os
from collections import defaultdict
from typing import Any

from aiokafka import AIOKafkaConsumer

from . import __version__
from .composition import compose_phrase, deterministic_operation_id
from .events import CloudEvent, build_operation_id, validate_no_prohibited_fields
from .imaging import ImageArtifact, sha256_bytes
from .kafka_client import create_consumer, create_producer, publish
from .minio_store import create_client, get_bytes, object_key_for, put_bytes
from .preprocessing_impl import preprocess_phrase_image

INPUT_TOPIC = os.environ.get("KAFKA_RASTERIZED_TOPIC", "rg.glyph-rasterized.v1")
OUTPUT_TOPIC = os.environ.get("KAFKA_PHRASE_COMPOSED_TOPIC", "rg.phrase-composed.v1")
OCR_INPUT_TOPIC = os.environ.get("KAFKA_PHRASE_COMPOSED_TOPIC", "rg.phrase-composed.v1")
OCR_OUTPUT_TOPIC = os.environ.get("KAFKA_OCR_IMAGES_TOPIC", "rg.ocr-images.v1")
BUCKET = os.environ.get("PIPELINE_BUCKET", "rube-goldberg-artifacts")
SOURCE = "image-pipeline"


async def run_worker() -> None:
    compose_consumer = await create_consumer([INPUT_TOPIC], group_id=GROUP_ID + "-compose")
    preprocess_consumer = await create_consumer(
        [OCR_INPUT_TOPIC], group_id=GROUP_ID + "-preprocess"
    )
    producer = await create_producer()
    minio = create_client()

    pending: dict[str, list[dict[str, Any]]] = defaultdict(list)
    timers: dict[str, asyncio.Task] = {}

    async def flush_run(run_id: str) -> None:
        records = pending.pop(run_id, [])
        timers.pop(run_id, None)
        if not records:
            return
        glyphs = _build_glyphs(records, minio)
        if glyphs:
            await _compose_and_publish(run_id, glyphs, minio, producer)

    def on_rasterized(run_id: str) -> None:
        if run_id in timers:
            timers[run_id].cancel()
        timers[run_id] = asyncio.get_running_loop().create_task(
            _delayed_flush(run_id, pending, timers, minio, producer)
        )

    async def consume_compose() -> None:
        consumer = compose_consumer
        while True:
            try:
                msg = await consumer.getone()
                event = msg.value
                data = event.get("data", {})
                run_id = data.get("runId")
                if not run_id:
                    continue
                if event.get("type") == "rg.glyph-rasterized.v1":
                    pending[run_id].append(data)
                    on_rasterized(run_id)
            except Exception as e:
                print(f"image-pipeline compose consumer error: {e}")
                try:
                    await consumer.stop()
                except Exception:
                    pass
                consumer = await create_consumer([INPUT_TOPIC], group_id=GROUP_ID + "-compose")

    async def consume_preprocess() -> None:
        consumer = preprocess_consumer
        while True:
            try:
                msg = await consumer.getone()
                event = msg.value
                data = event.get("data", {})
                run_id = data.get("runId")
                if not run_id:
                    continue
                if event.get("type") == "rg.phrase-composed.v1":
                    await _preprocess_and_publish(run_id, data, minio, producer)
            except Exception as e:
                print(f"image-pipeline preprocess consumer error: {e}")
                try:
                    await consumer.stop()
                except Exception:
                    pass
                consumer = await create_consumer(
                    [OCR_INPUT_TOPIC], group_id=GROUP_ID + "-preprocess"
                )

    try:
        await asyncio.gather(consume_compose(), consume_preprocess())
    finally:
        await compose_consumer.stop()
        await preprocess_consumer.stop()
        await producer.stop()


async def _delayed_flush(
    run_id: str,
    pending: dict[str, list[dict[str, Any]]],
    timers: dict[str, asyncio.Task],
    minio: Any,
    producer: Any,
) -> None:
    await asyncio.sleep(2)
    records = pending.pop(run_id, [])
    timers.pop(run_id, None)
    if records:
        glyphs = _build_glyphs(records, minio)
        if glyphs:
            await _compose_and_publish(run_id, glyphs, minio, producer)


def _build_glyphs(records: list[dict[str, Any]], minio: Any) -> list[Any] | None:
    from .composition import RasterizedGlyphInput

    drawable = [r for r in records if r.get("position") is not None and r.get("raster")]
    if not drawable:
        return None

    glyphs: list[RasterizedGlyphInput] = []
    for r in sorted(drawable, key=lambda r: r["position"]):
        raster = r.get("raster", {})
        object_key = raster.get("objectKey", "")
        image_bytes = None
        if object_key:
            try:
                image_bytes = get_bytes(minio, BUCKET, object_key)
            except Exception:
                image_bytes = None
        glyphs.append(
            RasterizedGlyphInput(
                position=r["position"],
                object_key=object_key,
                minio_uri=None,
                sha256=raster.get("sha256", ""),
                width=raster.get("width", 0),
                height=raster.get("height", 0),
                advance_width=1.0,
                baseline=0.0,
                kind="DRAWABLE",
                image_bytes=image_bytes,
            )
        )
    return glyphs


async def _compose_and_publish(run_id: str, glyphs: list[Any], minio: Any, producer: Any) -> None:
    result = compose_phrase(glyphs)
    phrase_key = object_key_for(run_id, result.phrase_image.sha256, "phrase.png")
    manifest_key = object_key_for(run_id, result.phrase_image.sha256, "manifest.json")

    put_bytes(minio, BUCKET, phrase_key, result.image_bytes, "image/png")
    put_bytes(minio, BUCKET, manifest_key, result.manifest_bytes, "application/json")

    event = _build_phrase_composed_event(run_id, result, phrase_key, manifest_key)
    await publish(producer, OUTPUT_TOPIC, event)


def _build_phrase_composed_event(
    run_id: str, result: Any, phrase_key: str, manifest_key: str
) -> dict[str, Any]:
    step_id = build_operation_id(run_id, "compose-phrase", 1, result.phrase_image.sha256)
    layout = []
    for entry in result.manifest.layout:
        layout.append(
            {
                "position": entry.position,
                "bbox": {
                    "x": entry.x,
                    "y": entry.y,
                    "width": entry.width,
                    "height": entry.height,
                },
            }
        )
    data = {
        "runId": run_id,
        "stepId": step_id,
        "attempt": 1,
        "inputMaturity": 40,
        "outputMaturity": 50,
        "inputArtifacts": [],
        "outputArtifacts": [result.phrase_image.sha256, result.phrase_image.sha256 + "-manifest"],
        "transformation": {"name": "compose-phrase", "version": "1.0"},
        "compositionManifest": {"layout": layout},
        "phraseImage": {
            "objectKey": phrase_key,
            "width": result.phrase_image.width,
            "height": result.phrase_image.height,
            "sha256": result.phrase_image.sha256,
        },
    }
    validate_no_prohibited_fields(data)
    event = CloudEvent(
        id=deterministic_event_id(run_id, "compose-phrase", 1, result.phrase_image.sha256),
        source=SOURCE,
        type="rg.phrase-composed.v1",
        subject=f"runs/{run_id}",
        correlationid=run_id,
        data=data,
    )
    return event.to_dict()


async def _preprocess_and_publish(
    run_id: str, data: dict[str, Any], minio: Any, producer: Any
) -> None:
    phrase_image_info = data.get("phraseImage", {})
    phrase_key = phrase_image_info.get("objectKey", "")
    if not phrase_key:
        return

    try:
        phrase_bytes = get_bytes(minio, BUCKET, phrase_key)
    except Exception:
        return

    from .imaging import CompositionManifest, LayoutEntry

    layout = []
    for entry in data.get("compositionManifest", {}).get("layout", []):
        layout.append(
            LayoutEntry(
                position=entry["position"],
                x=entry["bbox"]["x"],
                y=entry["bbox"]["y"],
                width=entry["bbox"]["width"],
                height=entry["bbox"]["height"],
                advance_width=1.0,
                baseline=0.0,
            )
        )
    manifest = CompositionManifest(layout=layout, total_width=0, total_height=0)

    result = preprocess_phrase_image(phrase_bytes, manifest)
    ocr_key = object_key_for(run_id, result.ocr_image.sha256, "ocr-phrase.png")
    put_bytes(minio, BUCKET, ocr_key, result.ocr_image_bytes, "image/png")

    crop_keys = []
    for pos, crop_bytes in result.crops_bytes.items():
        crop_key = object_key_for(run_id, result.ocr_image.sha256, f"crop-{pos}.png")
        put_bytes(minio, BUCKET, crop_key, crop_bytes, "image/png")
        crop_keys.append(
            {
                "position": pos,
                "objectKey": crop_key,
                "x": result.position_crops[pos].x,
                "y": result.position_crops[pos].y,
                "width": result.position_crops[pos].width,
                "height": result.position_crops[pos].height,
            }
        )

    event = _build_ocr_prepared_event(run_id, result, ocr_key, crop_keys)
    await publish(producer, OCR_OUTPUT_TOPIC, event)


def _build_ocr_prepared_event(
    run_id: str, result: Any, ocr_key: str, crop_keys: list[dict[str, Any]]
) -> dict[str, Any]:
    step_id = build_operation_id(run_id, "prepare-ocr-image", 1, result.ocr_image.sha256)
    data = {
        "runId": run_id,
        "stepId": step_id,
        "attempt": 1,
        "inputMaturity": 50,
        "outputMaturity": 60,
        "inputArtifacts": [result.ocr_image.sha256],
        "outputArtifacts": [result.ocr_image.sha256, *[c["objectKey"] for c in crop_keys]],
        "transformation": {"name": "prepare-ocr-image", "version": "1.0"},
        "ocrImage": {
            "objectKey": ocr_key,
            "width": result.ocr_image.width,
            "height": result.ocr_image.height,
            "sha256": result.ocr_image.sha256,
        },
        "positionCrops": crop_keys,
    }
    validate_no_prohibited_fields(data)
    event = CloudEvent(
        id=deterministic_event_id(run_id, "prepare-ocr-image", 1, result.ocr_image.sha256),
        source=SOURCE,
        type="rg.ocr-images.v1",
        subject=f"runs/{run_id}",
        correlationid=run_id,
        data=data,
    )
    return event.to_dict()


def deterministic_event_id(run_id: str, step: str, attempt: int, data_hash: str) -> str:
    import hashlib

    payload = json.dumps(
        {"runId": run_id, "step": step, "attempt": attempt, "dataHash": data_hash},
        sort_keys=True,
    )
    return "01H8" + hashlib.sha256(payload.encode()).hexdigest()[:20]


GROUP_ID = os.environ.get("KAFKA_CONSUMER_GROUP", "image-pipeline-v1")
