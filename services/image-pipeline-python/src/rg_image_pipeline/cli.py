from __future__ import annotations

import argparse
import json
import sys

from . import __version__
from .composition import RasterizedGlyphInput, compose_phrase
from .imaging import CompositionManifest, LayoutEntry
from .preprocessing import PreprocessParams
from .preprocessing_impl import preprocess_phrase_image


def run_compose_once(args: argparse.Namespace) -> int:
    glyphs: list[RasterizedGlyphInput] = []
    for glyph_file in sorted(args.glyph_files):
        with open(glyph_file, "rb") as f:
            data = json.load(f)
        position = data.get("position", 0)
        object_key = data.get("object_key", "")
        sha256 = data.get("sha256", "")
        image_bytes = data.get("image_bytes")
        if isinstance(image_bytes, str):
            try:
                image_bytes = bytes.fromhex(image_bytes)
            except ValueError:
                image_bytes = None
        glyphs.append(
            RasterizedGlyphInput(
                position=position,
                object_key=object_key,
                minio_uri=data.get("minio_uri"),
                sha256=sha256,
                width=data.get("width", 0),
                height=data.get("height", 0),
                advance_width=data.get("advance_width", 1.0),
                baseline=data.get("baseline", 0.0),
                kind=data.get("kind", "DRAWABLE"),
                image_bytes=image_bytes,
            )
        )
    if not glyphs:
        print("error: no glyph inputs provided", file=sys.stderr)
        return 1
    result = compose_phrase(glyphs, scale_factor=float(args.scale_factor or 1))
    if args.output_phrase_image:
        with open(args.output_phrase_image, "wb") as f:
            f.write(result.image_bytes)
    if args.output_manifest:
        manifest_data = {
            "layout": [
                {
                    "position": e.position,
                    "x": e.x,
                    "y": e.y,
                    "width": e.width,
                    "height": e.height,
                    "advanceWidth": e.advance_width,
                    "baseline": e.baseline,
                }
                for e in result.manifest.layout
            ],
            "totalWidth": result.manifest.total_width,
            "totalHeight": result.manifest.total_height,
        }
        with open(args.output_manifest, "w") as f:
            json.dump(manifest_data, f, indent=2, sort_keys=True)
    print(
        json.dumps(
            {
                "phraseImageSha256": result.phrase_image.sha256,
                "phraseImageWidth": result.phrase_image.width,
                "phraseImageHeight": result.phrase_image.height,
                "byteCount": result.phrase_image.byte_count,
            },
            indent=2,
        )
    )
    return 0


def run_preprocess_once(args: argparse.Namespace) -> int:
    with open(args.phrase_image, "rb") as f:
        phrase_bytes = f.read()
    with open(args.composition_manifest) as f:
        manifest_data = json.load(f)
    manifest = CompositionManifest(
        layout=[
            LayoutEntry(
                position=e["position"],
                x=e["x"],
                y=e["y"],
                width=e["width"],
                height=e["height"],
                advance_width=e.get("advanceWidth", 1.0),
                baseline=e.get("baseline", 0.0),
            )
            for e in manifest_data.get("layout", [])
        ],
        total_width=manifest_data.get("totalWidth", 0),
        total_height=manifest_data.get("totalHeight", 0),
    )
    params = PreprocessParams(
        contrast_factor=float(args.contrast_factor),
        threshold_value=args.threshold,
        border_size=args.border_size,
        scale_factor=args.scale_factor,
        noise_removal_blob_threshold=args.noise_removal,
    )
    result = preprocess_phrase_image(phrase_bytes, manifest, params)
    if args.output_ocr_image:
        with open(args.output_ocr_image, "wb") as f:
            f.write(result.ocr_image_bytes)
    crops_dir = args.output_crops_dir
    if crops_dir:
        import os

        os.makedirs(crops_dir, exist_ok=True)
        for pos, data in result.crops_bytes.items():
            with open(f"{crops_dir}/crop-position-{pos}.png", "wb") as f:
                f.write(data)
    if args.output_report:
        with open(args.output_report, "w") as f:
            json.dump(result.report, f, indent=2, sort_keys=True)
    print(
        json.dumps(
            {
                "ocrImageSha256": result.ocr_image.sha256,
                "ocrImageWidth": result.ocr_image.width,
                "ocrImageHeight": result.ocr_image.height,
                "positionCrops": len(result.position_crops),
            },
            indent=2,
        )
    )
    return 0


def version_command() -> int:
    print(f"image-pipeline {__version__}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="image-pipeline",
        description="Phrase composition and OCR preprocessing (Milestone 7)",
    )
    parser.add_argument(
        "-V",
        "--version",
        action="store_true",
        help="Print version and exit",
    )
    sub = parser.add_subparsers(dest="command")
    sub.required = False

    compose_cmd = sub.add_parser("compose", help="Run phrase composition once")
    compose_cmd.add_argument(
        "glyph_files",
        nargs="*",
        help="Paths to JSON files describing rasterized glyph inputs",
    )
    compose_cmd.add_argument(
        "--output-phrase-image",
        default=None,
        help="Path to write the composed phrase PNG",
    )
    compose_cmd.add_argument(
        "--output-manifest",
        default=None,
        help="Path to write the composition manifest JSON",
    )
    compose_cmd.add_argument(
        "--scale-factor",
        default=None,
        help="Optional integer scale factor for glyph images",
    )

    prep_cmd = sub.add_parser("preprocess", help="Run OCR preprocessing once")
    prep_cmd.add_argument(
        "--phrase-image",
        required=True,
        help="Path to the composed phrase PNG",
    )
    prep_cmd.add_argument(
        "--composition-manifest",
        required=True,
        help="Path to the composition manifest JSON",
    )
    prep_cmd.add_argument(
        "--output-ocr-image",
        default=None,
        help="Path to write the OCR-prepared image PNG",
    )
    prep_cmd.add_argument(
        "--output-crops-dir",
        default=None,
        help="Directory to write individual position crop PNGs",
    )
    prep_cmd.add_argument(
        "--output-report",
        default=None,
        help="Path to write the preprocessing report JSON",
    )
    prep_cmd.add_argument(
        "--contrast-factor",
        type=float,
        default=1.5,
        help="Contrast enhancement factor (default: 1.5)",
    )
    prep_cmd.add_argument(
        "--threshold",
        type=int,
        default=128,
        help="Binarization threshold 0-255 (default: 128)",
    )
    prep_cmd.add_argument(
        "--border-size",
        type=int,
        default=10,
        help="Border size in pixels (default: 10)",
    )
    prep_cmd.add_argument(
        "--scale-factor",
        type=int,
        default=2,
        help="Integer scale factor for OCR image (default: 2)",
    )
    prep_cmd.add_argument(
        "--noise-removal",
        type=int,
        default=50,
        help="Blob removal size threshold (default: 50, 0 to disable)",
    )

    serve_cmd = sub.add_parser("serve", help="Run Kafka worker for composition and preprocessing")
    serve_cmd.set_defaults(scale_factor=1)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.version or args.command is None:
        return version_command()

    if args.command == "compose":
        return run_compose_once(args)
    if args.command == "preprocess":
        return run_preprocess_once(args)
    if args.command == "serve":
        import asyncio

        from .worker import run_worker

        asyncio.run(run_worker())
        return 0
    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
