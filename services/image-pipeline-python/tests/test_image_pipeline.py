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
from rg_image_pipeline.worker import _build_glyphs, _preprocess_and_publish


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

    def test_compose_phrase_scales_oversized_glyph_to_em(self):
        glyph = make_test_png(284, 433)
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="a",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=284,
                height=433,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
                pixel_density=1024.0 / 433.0,
            ),
        ]
        result = compose_phrase(inputs)
        entry = result.manifest.layout[0]
        self.assertLessEqual(entry.height, 433)
        self.assertLessEqual(entry.x + entry.width, result.phrase_image.width)
        self.assertLessEqual(entry.y + entry.height, result.phrase_image.height)

    def test_compose_phrase_scales_oversized_glyph_without_density(self):
        glyph = make_test_png(284, 433)
        inputs = [
            RasterizedGlyphInput(
                position=0,
                object_key="a",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=284,
                height=433,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
            ),
        ]
        result = compose_phrase(inputs)
        entry = result.manifest.layout[0]
        self.assertLessEqual(entry.height, 433)
        self.assertLessEqual(entry.y + entry.height, result.phrase_image.height)

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

    def test_preprocess_flattens_transparent_background(self):
        import io

        from PIL import Image as PILImage

        glyph = make_test_png(32, 64, (0, 0, 0, 255))
        canvas = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        glyph_img = PILImage.open(io.BytesIO(glyph))
        canvas.paste(glyph_img, (0, 0), glyph_img)
        phrase_bytes = encode_png(canvas)
        manifest = CompositionManifest(
            layout=[
                LayoutEntry(
                    position=0,
                    x=0,
                    y=0,
                    width=32,
                    height=64,
                    advance_width=1.0,
                    baseline=51,
                )
            ],
            total_width=64,
            total_height=64,
        )
        params = PreprocessParams(
            contrast_factor=1.0,
            threshold_value=128,
            border_size=0,
            scale_factor=1,
            noise_removal_blob_threshold=0,
        )
        prep = preprocess_phrase_image(phrase_bytes, manifest, params)
        ocr = Image.open(io.BytesIO(prep.ocr_image_bytes)).convert("L")
        get_data_fn = getattr(ocr, "get_flattened_data", ocr.getdata)
        pixels = list(get_data_fn())
        self.assertGreater(sum(1 for p in pixels if p > 128), 0)
        self.assertIn(255, pixels)
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
        crops = sorted(prep.position_crops, key=lambda crop: crop.position)
        for crop in prep.position_crops:
            self.assertEqual(crop.object_key, f"ocr-crop-position-{crop.position}.png")
            self.assertIn(crop.position, prep.crops_bytes)
            self.assertTrue(prep.crops_bytes[crop.position].startswith(PNG_MAGIC))
        for previous, current in zip(crops, crops[1:], strict=False):
            self.assertLessEqual(previous.x + previous.width, current.x)

    def test_preprocess_gap_positions(self):
        glyph = make_test_png(32, 64, (0, 0, 0, 255))
        inputs = [
            RasterizedGlyphInput(
                position=pos,
                object_key=f"k{pos}",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=32,
                height=64,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
            )
            for pos in [0, 1, 2, 3, 4, 6, 7, 8, 9, 10]
        ]
        result = compose_phrase(inputs)
        params = PreprocessParams(
            threshold_value=128,
            border_size=5,
            scale_factor=1,
            contrast_factor=1.0,
            noise_removal_blob_threshold=0,
        )
        prep = preprocess_phrase_image(result.image_bytes, result.manifest, params)
        self.assertNotIn(5, prep.crops_bytes)
        self.assertIn(10, prep.crops_bytes)
        self.assertEqual(len(prep.position_crops), 10)
        self.assertEqual(prep.position_crops[-1].position, 10)

    def test_preprocess_publish_gap_positions(self):
        import asyncio

        from rg_image_pipeline import worker as worker_module

        glyph = make_test_png(32, 64, (0, 0, 0, 255))
        inputs = [
            RasterizedGlyphInput(
                position=pos,
                object_key=f"k{pos}",
                minio_uri=None,
                sha256=sha256_bytes(glyph),
                width=32,
                height=64,
                advance_width=1.0,
                kind="DRAWABLE",
                image_bytes=glyph,
            )
            for pos in [0, 1, 2, 3, 4, 6, 7, 8, 9, 10]
        ]
        result = compose_phrase(inputs)
        layout = [
            {
                "position": e.position,
                "bbox": {"x": e.x, "y": e.y, "width": e.width, "height": e.height},
            }
            for e in result.manifest.layout
        ]

        stored = {}

        class FakeMinio:
            def get_object(self, bucket, key):
                class Resp:
                    def read(self):
                        return stored[key]

                    def close(self):
                        pass

                    def release_conn(self):
                        pass

                return Resp()

            def put_object(self, bucket, key, data, length, content_type):
                stored[key] = data.read()

        published = []

        async def fake_publish(producer, topic, event):
            published.append((topic, event))

        data = {
            "runId": "run-gap",
            "phraseImage": {"objectKey": "phrase-key"},
            "compositionManifest": {"layout": layout},
        }
        stored["phrase-key"] = result.image_bytes

        with patch.object(worker_module, "publish", side_effect=fake_publish):
            asyncio.run(_preprocess_and_publish("run-gap", data, FakeMinio(), None))

        self.assertEqual(len(published), 1)
        topic, event = published[0]
        self.assertEqual(topic, "rg.ocr-images.v1")
        crop_positions = [c["position"] for c in event["data"]["positionCrops"]]
        self.assertEqual(crop_positions, [0, 1, 2, 3, 4, 6, 7, 8, 9, 10])
        for crop in event["data"]["positionCrops"]:
            self.assertIn(crop["objectKey"], stored)

    def test_build_glyphs_includes_gap_records(self):
        glyph = make_test_png(10, 10)
        records = [
            {
                "position": 0,
                "raster": {"objectKey": "k0", "sha256": "a", "width": 10, "height": 10},
            },
            {
                "position": 5,
                "geometry": {"kind": "GAP_GEOMETRY", "advanceWidth": 0.6},
            },
            {
                "position": 6,
                "raster": {"objectKey": "k6", "sha256": "b", "width": 10, "height": 10},
            },
        ]

        class FakeMinio:
            def get_object(self, bucket, key):
                class Resp:
                    def read(self):
                        return glyph

                    def close(self):
                        pass

                    def release_conn(self):
                        pass

                return Resp()

        glyphs = _build_glyphs(records, FakeMinio())
        by_pos = {g.position: g for g in glyphs}
        self.assertEqual(set(by_pos.keys()), {0, 5, 6})
        self.assertEqual(by_pos[5].kind, "GAP")
        self.assertEqual(by_pos[5].advance_width, 0.6)
        self.assertIsNone(by_pos[5].image_bytes)
        self.assertEqual(by_pos[0].kind, "DRAWABLE")


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
