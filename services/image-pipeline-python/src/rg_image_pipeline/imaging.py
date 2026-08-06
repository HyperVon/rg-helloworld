from __future__ import annotations

import hashlib
import io
from dataclasses import dataclass, field

from PIL import Image

MIN_PNG_BYTES = 1
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


@dataclass(frozen=True)
class ImageArtifact:
    object_key: str
    width: int
    height: int
    sha256: str
    byte_count: int


@dataclass(frozen=True)
class LayoutEntry:
    position: int
    x: int
    y: int
    width: int
    height: int
    advance_width: float = 0.0
    baseline: float = 0.0


@dataclass
class CompositionManifest:
    layout: list[LayoutEntry] = field(default_factory=list)
    total_width: int = 0
    total_height: int = 0

    def bbox_for(self, position: int) -> LayoutEntry | None:
        for entry in self.layout:
            if entry.position == position:
                return entry
        return None

    def positions(self) -> list[int]:
        return [entry.position for entry in self.layout]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: str) -> str:
    with open(path, "rb") as f:
        return sha256_bytes(f.read())


def encode_png(image: Image.Image, optimize: bool = True) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG", optimize=optimize, format_args={"zlib_level": 9})
    data = buf.getvalue()
    if not data.startswith(PNG_MAGIC):
        raise RuntimeError("PNG encoding failure: invalid magic bytes")
    return data


def load_png_bytes(data: bytes) -> Image.Image:
    if not data.startswith(PNG_MAGIC):
        raise ValueError("input is not a PNG")
    return Image.open(io.BytesIO(data)).convert("RGBA")
