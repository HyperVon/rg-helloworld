import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "src"))

from PIL import Image

from rg_image_pipeline.composition import (
    RasterizedGlyphInput,
    compose_phrase,
    deterministic_operation_id,
)
from rg_image_pipeline.events import (
    CloudEvent,
    build_operation_id,
    deterministic_event_id,
    validate_no_prohibited_fields,
)
from rg_image_pipeline.imaging import (
    PNG_MAGIC,
    CompositionManifest,
    ImageArtifact,
    LayoutEntry,
    encode_png,
    load_png_bytes,
    sha256_bytes,
    sha256_file,
)
from rg_image_pipeline.preprocessing import PreprocessParams
from rg_image_pipeline.preprocessing_impl import preprocess_phrase_image


def make_test_png(width: int, height: int, color=(255, 255, 255, 255)) -> bytes:
    img = Image.new("RGBA", (width, height), color)
    return encode_png(img)


class TestImaging(unittest.TestCase):
    def test_encode_png_has_magic_bytes(self):
        img = Image.new("RGBA", (10, 10), (255, 255, 255, 255))
        data = encode_png(img)
        self.assertTrue(data.startswith(PNG_MAGIC))
        self.assertGreater(len(data), 0)

    def test_load_png_bytes_roundtrip(self):
        original = make_test_png(20, 30, (100, 150, 200, 255))
        img = load_png_bytes(original)
        self.assertEqual(img.size, (20, 30))
        self.assertEqual(img.mode, "RGBA")

    def test_load_png_bytes_rejects_non_png(self):
        with self.assertRaises(ValueError):
            load_png_bytes(b"not a png file")

    def test_sha256_bytes_deterministic(self):
        data = b"test data"
        self.assertEqual(sha256_bytes(data), sha256_bytes(data))
        self.assertNotEqual(sha256_bytes(data), sha256_bytes(b"other data"))

    def test_sha256_file(self):
        import tempfile

        with tempfile.NamedTemporaryFile(suffix=".bin", delete=False) as f:
            f.write(b"file content")
            path = f.name
        try:
            result = sha256_file(path)
            expected = sha256_bytes(b"file content")
            self.assertEqual(result, expected)
        finally:
            Path(path).unlink(missing_ok=True)

    def test_encode_png_rejects_invalid_magic(self):
        img = Image.new("RGBA", (10, 10), (255, 255, 255, 255))
        with (
            patch("rg_image_pipeline.imaging.PNG_MAGIC", b"INVALID"),
            self.assertRaises(RuntimeError),
        ):
            encode_png(img)


class TestComposition(unittest.TestCase):
    def test_compose_phrase_basic_two_glyphs(self):
        glyph_a = make_test_png(32, 64, (255, 0, 0, 255))
        glyph_b = make_test_png(32, 64, (0, 255, 0, 255))
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="a",
                minio_uri="minio://a",
                sha256=sha256_bytes(glyph_a),
                width=32,
                height=64,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph_a,
            ),
            RasterizedGlyphInput(
                position=1,
                object_key="b",
                minio_uri="minio://b",
                sha256=sha256_bytes(glyph_b),
                width=32,
                height=64,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph_b,
            ),
        ]
        result = compose_phrase(inputs)
        self.assertIsInstance(result.phrase_image, ImageArtifact)
        self.assertGreater(result.phrase_image.width, 0)
        self.assertGreater(result.phrase_image.height, 0)
        self.assertEqual(len(result.manifest.layout), 2)
        self.assertEqual(result.manifest.layout[0].position, 0)
        self.assertEqual(result.manifest.layout[1].position, 1)

    def test_compose_phrase_rejects_empty(self):
        with self.assertRaises(ValueError):
            compose_phrase([])

    def test_compose_phrase_rejects_duplicate_positions(self):
        glyph = make_test_png(10, 10)
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="a",
                minio_uri=None,
                sha256="abc",
                width=10,
                height=10,
                image_bytes=glyph,
            ),
            RasterizedGlyphInput(
                position=0,
                object_key="b",
                minio_uri=None,
                sha256="def",
                width=10,
                height=10,
                image_bytes=glyph,
            ),
        ]
        with self.assertRaises(ValueError):
            compose_phrase(inputs)

    def test_compose_phrase_with_gap(self):
        glyph = make_test_png(32, 64, (255, 0, 0, 255))
        gap_bytes = encode_png(Image.new("RGBA", (1, 1), (0, 0, 0, 0)))
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
            RasterizedGlyphInput(
                position=5,
                object_key="gap5",
                minio_uri=None,
                sha256=sha256_bytes(gap_bytes),
                width=1,
                height=1,
                advance_width=0.65,
                kind="GAP",
                image_bytes=None,
            ),
            RasterizedGlyphInput(
                position=6,
                object_key="g6",
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
        self.assertEqual(len(result.manifest.layout), 3)
        gap_entry = result.manifest.layout[1]
        self.assertEqual(gap_entry.position, 5)
        self.assertEqual(gap_entry.width, 0)
        self.assertEqual(gap_entry.height, 0)

    def test_compose_phrase_deterministic(self):
        glyph = make_test_png(32, 64, (100, 150, 200, 255))
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="a",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=32,
                height=64,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
            ),
        ]
        r1 = compose_phrase(inputs)
        r2 = compose_phrase(inputs)
        self.assertEqual(r1.image_bytes, r2.image_bytes)
        self.assertEqual(r1.phrase_image.sha256, r2.phrase_image.sha256)

    def test_compose_phrase_scales_glyphs(self):
        glyph = make_test_png(16, 32)
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="a",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=16,
                height=32,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
            ),
        ]
        result = compose_phrase(inputs, scale_factor=2.0)
        self.assertGreater(result.phrase_image.width, 0)

    def test_deterministic_operation_id(self):
        op1 = deterministic_operation_id("run-1", "step-1", 1, ["hash1"])
        op2 = deterministic_operation_id("run-1", "step-1", 1, ["hash1"])
        op3 = deterministic_operation_id("run-1", "step-1", 2, ["hash1"])
        self.assertEqual(op1, op2)
        self.assertNotEqual(op1, op3)


class TestPreprocessing(unittest.TestCase):
    def _make_phrase_image(self):
        glyph = make_test_png(32, 64, (0, 0, 0, 255))
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="a",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=32,
                height=64,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
            ),
        ]
        return compose_phrase(inputs)

    def test_preprocess_basic(self):
        result = self._make_phrase_image()
        params = PreprocessParams(
            contrast_factor=1.0,
            threshold_value=128,
            border_size=5,
            scale_factor=1,
            noise_removal_blob_threshold=0,
        )
        prep = preprocess_phrase_image(result.image_bytes, result.manifest, params)
        self.assertIsInstance(prep.ocr_image, ImageArtifact)
        self.assertGreater(prep.ocr_image.width, 0)
        self.assertGreater(prep.ocr_image.height, 0)
        self.assertGreater(len(prep.ocr_image_bytes), 0)
        self.assertGreater(len(prep.position_crops), 0)
        self.assertIn("threshold", prep.report)
        self.assertIn("scale", prep.report)
        self.assertIn("foregroundRatio", prep.report)

    def test_preprocess_with_threshold(self):
        result = self._make_phrase_image()
        params = PreprocessParams(threshold_value=100, border_size=10, scale_factor=2)
        prep = preprocess_phrase_image(result.image_bytes, result.manifest, params)
        self.assertEqual(prep.report["threshold"], 100)
        self.assertEqual(prep.report["scale"], 2)

    def test_preprocess_border_added(self):
        result = self._make_phrase_image()
        params_no_border = PreprocessParams(
            threshold_value=255,
            border_size=0,
            scale_factor=1,
            contrast_factor=1.0,
            noise_removal_blob_threshold=0,
        )
        prep_no_border = preprocess_phrase_image(
            result.image_bytes, result.manifest, params_no_border
        )
        params_border = PreprocessParams(
            threshold_value=255,
            border_size=20,
            scale_factor=1,
            contrast_factor=1.0,
            noise_removal_blob_threshold=0,
        )
        prep_border = preprocess_phrase_image(result.image_bytes, result.manifest, params_border)
        self.assertGreater(prep_border.ocr_image.width, prep_no_border.ocr_image.width)

    def test_preprocess_crops(self):
        result = self._make_phrase_image()
        params = PreprocessParams(
            threshold_value=128,
            border_size=5,
            scale_factor=1,
            contrast_factor=1.0,
            noise_removal_blob_threshold=0,
        )
        prep = preprocess_phrase_image(result.image_bytes, result.manifest, params)
        for crop in prep.position_crops:
            self.assertEqual(crop.object_key, f"ocr-crop-position-{crop.position}.png")
            self.assertIn(crop.position, prep.crops_bytes)
            self.assertTrue(prep.crops_bytes[crop.position].startswith(PNG_MAGIC))


class TestEvents(unittest.TestCase):
    def test_cloud_event_serialization(self):
        event = CloudEvent(
            specversion="1.0",
            id="evt-1",
            source="image-pipeline",
            type="rg.phrase-composed.v1",
            subject="runs/abc/glyphs/xyz",
            time="2026-08-05T10:00:00Z",
            data={"runId": "abc", "position": 0},
        )
        d = event.to_dict()
        self.assertEqual(d["specversion"], "1.0")
        self.assertEqual(d["id"], "evt-1")
        self.assertEqual(d["type"], "rg.phrase-composed.v1")
        b = event.to_bytes()
        import json

        parsed = json.loads(b)
        self.assertEqual(parsed["id"], "evt-1")

    def test_deterministic_event_id(self):
        id1 = deterministic_event_id("run-1", "step", 1, "hash")
        id2 = deterministic_event_id("run-1", "step", 1, "hash")
        id3 = deterministic_event_id("run-1", "step", 2, "hash")
        self.assertEqual(id1, id2)
        self.assertNotEqual(id1, id3)

    def test_validate_no_prohibited_fields_clean(self):
        data = {"runId": "abc", "position": 0, "data": {"foo": "bar"}}
        self.assertTrue(validate_no_prohibited_fields(data))

    def test_validate_no_prohibited_fields_prohibited(self):
        data = {"runId": "abc", "expectedCharacter": "H"}
        self.assertFalse(validate_no_prohibited_fields(data))
        data2 = {"message": "Hello World", "runId": "abc"}
        self.assertFalse(validate_no_prohibited_fields(data2))
        data3 = {"nested": {"unicodeCodePoint": 72}}
        self.assertFalse(validate_no_prohibited_fields(data3))

    def test_validate_no_prohibited_fields_list(self):
        data = {"items": [{"expectedCharacter": "H"}, {"runId": "abc"}]}
        self.assertFalse(validate_no_prohibited_fields(data))

    def test_build_operation_id(self):
        op1 = build_operation_id("run-1", "compose", 1, "hash1")
        op2 = build_operation_id("run-1", "compose", 1, "hash1")
        op3 = build_operation_id("run-1", "compose", 1, "hash2")
        self.assertEqual(op1, op2)
        self.assertNotEqual(op1, op3)


class TestCompositionManifest(unittest.TestCase):
    def test_positions(self):
        manifest = CompositionManifest(
            layout=[
                LayoutEntry(position=0, x=0, y=0, width=10, height=10),
                LayoutEntry(position=6, x=50, y=0, width=10, height=10),
            ]
        )
        self.assertEqual(manifest.positions(), [0, 6])

    def test_bbox_for(self):
        manifest = CompositionManifest(
            layout=[
                LayoutEntry(position=0, x=0, y=0, width=10, height=10),
            ]
        )
        entry = manifest.bbox_for(0)
        self.assertIsNotNone(entry)
        if entry:
            self.assertEqual(entry.position, 0)
        self.assertIsNone(manifest.bbox_for(99))


if __name__ == "__main__":
    unittest.main()
