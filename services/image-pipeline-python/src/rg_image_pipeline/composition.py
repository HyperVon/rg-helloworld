from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from typing import Any

from PIL import Image

from .imaging import (
    CompositionManifest,
    ImageArtifact,
    LayoutEntry,
    encode_png,
    load_png_bytes,
    sha256_bytes,
)


@dataclass
class RasterizedGlyphInput:
    position: int
    object_key: str
    minio_uri: str | None
    sha256: str
    width: int
    height: int
    advance_width: float = 1.0
    baseline: float = 0.0
    kind: str = "DRAWABLE"
    image_bytes: bytes | None = None
    pixel_density: float | None = None


@dataclass
class CompositionResult:
    manifest: CompositionManifest
    phrase_image: ImageArtifact
    image_bytes: bytes
    manifest_bytes: bytes


def deterministic_operation_id(
    run_id: str, step_id: str, attempt: int, input_hashes: list[str]
) -> str:
    payload = json.dumps(
        {"runId": run_id, "stepId": step_id, "attempt": attempt, "inputs": sorted(input_hashes)},
        sort_keys=True,
    )
    return hashlib.sha256(payload.encode()).hexdigest()


def compose_phrase(
    glyphs: list[RasterizedGlyphInput],
    phrase_margins: tuple[int, int, int, int] = (20, 10, 20, 10),
    em_square: float = 1024.0,
    scale_factor: float = 1.0,
) -> CompositionResult:
    if not glyphs:
        raise ValueError("cannot compose from empty glyph list")

    sorted_glyphs = sorted(glyphs, key=lambda g: g.position)
    seen = set()
    for g in sorted_glyphs:
        if g.position in seen:
            raise ValueError(f"duplicate position {g.position}")
        seen.add(g.position)

    margin_left, margin_top, margin_right, margin_bottom = phrase_margins
    total_advance = sum((1 if g.kind == "GAP" else 1) * g.advance_width for g in sorted_glyphs)
    pixels_per_em = 192
    max_glyph_height = max(
        (g.height for g in sorted_glyphs if g.kind == "DRAWABLE" and g.image_bytes is not None),
        default=pixels_per_em,
    )
    phrase_height = max(pixels_per_em, max_glyph_height) + margin_top + margin_bottom

    advance_width = max(1, int(total_advance * pixels_per_em) + margin_left + margin_right)
    total_glyph_width = 0
    for glyph in sorted_glyphs:
        advance_pixels = max(1, int(glyph.advance_width * pixels_per_em))
        if glyph.kind == "DRAWABLE" and glyph.image_bytes is not None:
            img_width = glyph.width
            if scale_factor != 1.0:
                img_width = max(1, int(img_width * scale_factor))
            actual_width = img_width
        else:
            actual_width = advance_pixels
        total_glyph_width += max(advance_pixels, actual_width)
    phrase_width = max(advance_width, total_glyph_width + margin_left + margin_right)

    canvas = Image.new("RGBA", (phrase_width, phrase_height), (0, 0, 0, 0))
    layout = []
    x_offset = margin_left
    for glyph in sorted_glyphs:
        entry = LayoutEntry(
            position=glyph.position,
            x=x_offset,
            y=margin_top,
            width=0,
            height=0,
            advance_width=glyph.advance_width,
            baseline=margin_top + int(pixels_per_em * 0.8),
        )
        if glyph.kind == "DRAWABLE" and glyph.image_bytes is not None:
            img = load_png_bytes(glyph.image_bytes)
            img_width, img_height = img.size
            if scale_factor != 1.0:
                new_size = (
                    max(1, int(img_width * scale_factor)),
                    max(1, int(img_height * scale_factor)),
                )
                img = img.resize(new_size, Image.Resampling.LANCZOS)
                img_width, img_height = new_size
            paste_x = x_offset
            paste_y = margin_top
            canvas.paste(img, (paste_x, paste_y), img)
            entry = LayoutEntry(
                position=glyph.position,
                x=paste_x,
                y=paste_y,
                width=img_width,
                height=img_height,
                advance_width=glyph.advance_width,
                baseline=paste_y + img_height * 0.8,
            )
        layout.append(entry)
        advance_pixels = max(1, int(glyph.advance_width * pixels_per_em))
        actual_width = (
            entry.width
            if glyph.kind == "DRAWABLE" and glyph.image_bytes is not None
            else advance_pixels
        )
        x_offset += max(advance_pixels, actual_width)

    manifest = CompositionManifest(
        layout=layout,
        total_width=phrase_width,
        total_height=phrase_height,
    )
    image_bytes = encode_png(canvas)
    image_artifact = ImageArtifact(
        object_key="",
        width=phrase_width,
        height=phrase_height,
        sha256=sha256_bytes(image_bytes),
        byte_count=len(image_bytes),
    )
    manifest_bytes = json.dumps(
        {
            "layout": [_entry_to_dict(e) for e in layout],
            "totalWidth": phrase_width,
            "totalHeight": phrase_height,
        },
        sort_keys=True,
    ).encode()
    return CompositionResult(
        manifest=manifest,
        phrase_image=image_artifact,
        image_bytes=image_bytes,
        manifest_bytes=manifest_bytes,
    )


def _glyph_scale(
    img_width: int,
    img_height: int,
    pixel_density: float | None,
    pixels_per_em: int,
    em_square: float,
    scale_factor: float,
) -> float:
    if pixel_density and pixel_density > 0:
        base = pixels_per_em * pixel_density / em_square
    else:
        max_dim = max(img_width, img_height)
        base = pixels_per_em / max_dim if max_dim > pixels_per_em else 1.0
    return base * scale_factor


def _entry_to_dict(entry: LayoutEntry) -> dict[str, Any]:
    return {
        "position": entry.position,
        "x": entry.x,
        "y": entry.y,
        "width": entry.width,
        "height": entry.height,
        "advanceWidth": entry.advance_width,
        "baseline": entry.baseline,
    }
