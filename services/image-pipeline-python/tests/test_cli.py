import io
import json
import sys
import tempfile
import unittest
from argparse import Namespace
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from rg_image_pipeline.cli import main, run_compose_once, version_command
from rg_image_pipeline.composition import RasterizedGlyphInput, compose_phrase
from rg_image_pipeline.imaging import encode_png, sha256_bytes


def make_glyph_bytes(width: int, height: int, color=(255, 255, 255, 255)) -> bytes:
    img = Image.new("RGBA", (width, height), color)
    return encode_png(img)


class VersionCommandTest(unittest.TestCase):
    def test_version_command(self):
        with redirect_stdout(io.StringIO()) as f:
            result = version_command()
        self.assertEqual(result, 0)
        self.assertIn("image-pipeline", f.getvalue())


class MainCLITest(unittest.TestCase):
    def test_main_version_flag(self):
        with redirect_stdout(io.StringIO()) as f:
            result = main(["--version"])
        self.assertEqual(result, 0)
        self.assertIn("image-pipeline", f.getvalue())

    def test_main_no_args_shows_version(self):
        with redirect_stdout(io.StringIO()) as f:
            result = main([])
        self.assertEqual(result, 0)
        self.assertIn("image-pipeline", f.getvalue())

    def test_main_help(self):
        with (
            self.assertRaises(SystemExit) as ctx,
            redirect_stdout(io.StringIO()),
            redirect_stderr(io.StringIO()),
        ):
            main(["--help"])
        self.assertEqual(ctx.exception.code, 0)


class ComposeCLITest(unittest.TestCase):
    def test_compose_once_no_files(self):
        args = Namespace(
            glyph_files=[],
            output_phrase_image=None,
            output_manifest=None,
            scale_factor=None,
        )
        result = run_compose_once(args)
        self.assertEqual(result, 1)

    def test_compose_once_with_glyphs(self):
        glyph_bytes = make_glyph_bytes(32, 64, (255, 0, 0, 255))
        glyph_hash = sha256_bytes(glyph_bytes)
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as f:
            json.dump(
                {
                    "position": 0,
                    "object_key": "g-0",
                    "sha256": glyph_hash,
                    "width": 32,
                    "height": 64,
                    "advance_width": 1.0,
                    "kind": "DRAWABLE",
                    "image_bytes": glyph_bytes.hex(),
                },
                f,
            )
            glyph_file = f.name

        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as png_f:
            out_png = png_f.name
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as man_f:
            out_manifest = man_f.name
        try:
            with redirect_stdout(io.StringIO()) as out:
                result = main(
                    [
                        "compose",
                        glyph_file,
                        "--output-phrase-image",
                        out_png,
                        "--output-manifest",
                        out_manifest,
                    ]
                )
            self.assertEqual(result, 0)
            output = json.loads(out.getvalue())
            self.assertIn("phraseImageSha256", output)
            self.assertGreater(output["phraseImageWidth"], 0)
            self.assertGreater(output["phraseImageHeight"], 0)
            self.assertTrue(Path(out_png).exists())
            self.assertTrue(Path(out_manifest).exists())
            with open(out_manifest) as f:
                manifest = json.load(f)
            self.assertIn("layout", manifest)
        finally:
            Path(glyph_file).unlink(missing_ok=True)
            Path(out_png).unlink(missing_ok=True)
            Path(out_manifest).unlink(missing_ok=True)


class PreprocessCLITest(unittest.TestCase):
    def setUp(self):
        glyph = make_glyph_bytes(32, 64, (255, 0, 0, 255))
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="g0",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=32,
                height=64,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
            ),
        ]
        result = compose_phrase(inputs)
        self.phrase_bytes = result.image_bytes
        self.manifest_data = {
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

    def test_preprocess_once(self):
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as pf:
            pf.write(self.phrase_bytes)
            phrase_file = pf.name
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json", delete=False) as mf:
            json.dump(self.manifest_data, mf)
            manifest_file = mf.name
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as ocr_f:
            ocr_out = ocr_f.name
        crops_dir = tempfile.mkdtemp()
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as rep_f:
            report_file = rep_f.name
        try:
            with redirect_stdout(io.StringIO()) as out:
                result = main(
                    [
                        "preprocess",
                        "--phrase-image",
                        phrase_file,
                        "--composition-manifest",
                        manifest_file,
                        "--output-ocr-image",
                        ocr_out,
                        "--output-crops-dir",
                        crops_dir,
                        "--output-report",
                        report_file,
                        "--contrast-factor",
                        "1.0",
                        "--threshold",
                        "128",
                        "--border-size",
                        "5",
                        "--scale-factor",
                        "1",
                        "--noise-removal",
                        "0",
                    ]
                )
            self.assertEqual(result, 0)
            output = json.loads(out.getvalue())
            self.assertIn("ocrImageSha256", output)
            self.assertGreaterEqual(output["positionCrops"], 1)
            self.assertTrue(Path(ocr_out).exists())
            self.assertTrue(Path(report_file).exists())
            self.assertTrue(Path(crops_dir).exists())
            crop_files = list(Path(crops_dir).glob("*.png"))
            self.assertGreater(len(crop_files), 0)
        finally:
            Path(phrase_file).unlink(missing_ok=True)
            Path(manifest_file).unlink(missing_ok=True)
            Path(ocr_out).unlink(missing_ok=True)
            Path(report_file).unlink(missing_ok=True)
            import shutil

            shutil.rmtree(crops_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
