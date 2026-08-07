from __future__ import annotations

import io
from typing import Any

import numpy as np
from PIL import Image, ImageOps

from .imaging import (
    CompositionManifest,
    ImageArtifact,
    encode_png,
    sha256_bytes,
)
from .preprocessing import PositionCrop, PreprocessParams, PreprocessResult


def preprocess_phrase_image(
    phrase_image_bytes: bytes,
    manifest: CompositionManifest,
    params: PreprocessParams | None = None,
) -> PreprocessResult:
    params = params or PreprocessParams()
    img = _flatten_on_white(load_phrase_image(phrase_image_bytes))
    gray = ImageOps.grayscale(img)
    if params.contrast_factor != 1.0:
        gray = ImageOps.autocontrast(gray, cutoff=params.contrast_factor)
    enhanced = gray.convert("L")
    if params.threshold_value < 255:
        table = [0 if i < params.threshold_value else 255 for i in range(256)]
        enhanced = enhanced.point(table, mode="1").convert("L")
    if params.noise_removal_blob_threshold > 0:
        enhanced = _remove_noise(enhanced, params.noise_removal_blob_threshold)
    if params.border_size > 0:
        enhanced = ImageOps.expand(enhanced, border=params.border_size, fill=255)
    if params.scale_factor > 1:
        new_w = enhanced.width * params.scale_factor
        new_h = enhanced.height * params.scale_factor
        enhanced = enhanced.resize((new_w, new_h), Image.Resampling.NEAREST)
    ocr_image_bytes = encode_png(enhanced.convert("RGBA"))
    ocr_artifact = ImageArtifact(
        object_key="",
        width=enhanced.width,
        height=enhanced.height,
        sha256=sha256_bytes(ocr_image_bytes),
        byte_count=len(ocr_image_bytes),
    )
    position_crops, crops_bytes = _make_crops(
        enhanced, manifest, params.scale_factor, params.border_size
    )
    report = _build_report(enhanced, params, phrase_image_bytes)
    return PreprocessResult(
        ocr_image=ocr_artifact,
        ocr_image_bytes=ocr_image_bytes,
        position_crops=position_crops,
        crops_bytes=crops_bytes,
        report=report,
    )


def load_phrase_image(data: bytes) -> Image.Image:
    return Image.open(io.BytesIO(data))


def _flatten_on_white(img: Image.Image) -> Image.Image:
    if img.mode != "RGBA":
        return img
    background = Image.new("RGBA", img.size, (255, 255, 255, 255))
    background.paste(img, mask=img.split()[3])
    return background.convert("RGB")


def _remove_noise(img: Image.Image, threshold: int) -> Image.Image:
    arr = np.array(img)
    binary = arr < 128
    rows, cols = binary.shape
    component_id = 0
    component_map = np.zeros_like(arr)
    kept_ids: set[int] = set()
    for i in range(rows):
        for j in range(cols):
            if binary[i, j] and component_map[i, j] == 0:
                stack = [(i, j)]
                component: list[tuple[int, int]] = []
                component_id += 1
                while stack:
                    ci, cj = stack.pop()
                    if not (0 <= ci < rows and 0 <= cj < cols):
                        continue
                    if not binary[ci, cj] or component_map[ci, cj]:
                        continue
                    component_map[ci, cj] = component_id
                    component.append((ci, cj))
                    stack.extend([(ci + 1, cj), (ci - 1, cj), (ci, cj + 1), (ci, cj - 1)])
                if len(component) >= threshold:
                    kept_ids.add(component_id)
    result = arr.copy()
    result[(binary & ~np.isin(component_map, list(kept_ids)))] = 255
    return Image.fromarray(result)


def _make_crops(
    img: Image.Image,
    manifest: CompositionManifest,
    scale_factor: int,
    border_size: int = 0,
    crop_padding: int = 8,
) -> tuple[list[PositionCrop], dict[int, bytes]]:
    scale = scale_factor if scale_factor > 0 else 1
    border = border_size * scale
    pad = crop_padding * scale
    position_crops: list[PositionCrop] = []
    crops_bytes: dict[int, bytes] = {}
    for index, entry in enumerate(manifest.layout):
        glyph_left = entry.x * scale + border
        glyph_top = entry.y * scale + border
        glyph_right = glyph_left + max(1, entry.width * scale)
        glyph_bottom = glyph_top + max(1, entry.height * scale)
        x = max(0, glyph_left - pad)
        y = max(0, glyph_top - pad)
        right = min(img.width, glyph_right + pad)
        if index + 1 < len(manifest.layout):
            next_entry = manifest.layout[index + 1]
            next_left = next_entry.x * scale + border
            right = min(right, next_left)
        if index > 0:
            previous_entry = manifest.layout[index - 1]
            previous_right = (
                previous_entry.x * scale + border + max(1, previous_entry.width * scale)
            )
            x = max(x, previous_right)
        x = min(x, max(0, img.width - 1))
        y = min(y, max(0, img.height - 1))
        right = min(img.width, max(x + 1, right))
        bottom = min(img.height, glyph_bottom + pad)
        w = max(1, right - x)
        h = max(1, bottom - y)
        crop_img = img.crop((x, y, x + w, y + h))
        crop_bytes = encode_png(crop_img)
        object_key = f"ocr-crop-position-{entry.position}.png"
        position_crops.append(
            PositionCrop(
                position=entry.position,
                object_key=object_key,
                x=x,
                y=y,
                width=w,
                height=h,
            )
        )
        crops_bytes[entry.position] = crop_bytes
    return position_crops, crops_bytes


def _build_report(
    img: Image.Image,
    params: PreprocessParams,
    original_bytes: bytes,
) -> dict[str, Any]:
    arr = np.array(img.convert("L"))
    foreground = int(np.sum(arr < 128))
    total = arr.size
    ratio = foreground / total if total > 0 else 0.0
    return {
        "threshold": params.threshold_value,
        "scale": params.scale_factor,
        "foregroundRatio": float(ratio),
        "connectedComponentCount": 0,
        "originalSha256": sha256_bytes(original_bytes),
        "preprocessedSha256": sha256_bytes(encode_png(img)),
    }
