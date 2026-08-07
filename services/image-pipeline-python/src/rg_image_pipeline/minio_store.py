from __future__ import annotations

import hashlib
import io
import os
from typing import Any

from minio import Minio
from minio.error import S3Error


def _default_bucket() -> str:
    return os.environ.get("PIPELINE_BUCKET", "rube-goldberg-artifacts")


def create_client() -> Minio:
    endpoint = os.environ.get("MINIO_ENDPOINT", "minio.rube-goldberg.svc.cluster.local:9000")
    access_key = os.environ.get("MINIO_ACCESS_KEY", os.environ.get("MINIO_ROOT_USER", ""))
    secret_key = os.environ.get("MINIO_SECRET_KEY", os.environ.get("MINIO_ROOT_PASSWORD", ""))
    secure = (
        endpoint.startswith("https://") or os.environ.get("MINIO_SECURE", "false").lower() == "true"
    )
    host = endpoint.split("://")[-1] if "://" in endpoint else endpoint
    return Minio(host, access_key=access_key, secret_key=secret_key, secure=secure)


def put_bytes(
    client: Minio,
    bucket: str,
    key: str,
    data: bytes,
    content_type: str = "application/octet-stream",
) -> str:
    sha256 = hashlib.sha256(data).hexdigest()
    client.put_object(bucket, key, io.BytesIO(data), length=len(data), content_type=content_type)
    return sha256


def get_bytes(client: Minio, bucket: str, key: str) -> bytes:
    response = client.get_object(bucket, key)
    try:
        return response.read()
    finally:
        response.close()
        response.release_conn()


def object_key_for(run_id: str, artifact_id: str, filename: str) -> str:
    return f"artifacts/{artifact_id}/{filename}"
