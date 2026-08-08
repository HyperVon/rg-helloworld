from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from .imaging import ImageArtifact


@dataclass
class PreprocessParams:
    contrast_factor: float = 1.5
    threshold_value: int = 128
    border_size: int = 16
    scale_factor: int = 2
    noise_removal_blob_threshold: int = 25


@dataclass
class PositionCrop:
    position: int
    object_key: str
    x: int
    y: int
    width: int
    height: int


@dataclass
class PreprocessResult:
    ocr_image: ImageArtifact
    ocr_image_bytes: bytes
    position_crops: list[PositionCrop]
    crops_bytes: dict[int, bytes]
    report: dict[str, Any]
