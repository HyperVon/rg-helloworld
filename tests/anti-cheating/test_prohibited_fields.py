#!/usr/bin/env python3
"""Anti-cheating test: ensure prohibited plaintext fields never appear after glyph planning.

Implements architecture section 7.4 ("Static enforcement"): a repository test that
scans event schemas after `GlyphBlueprintProduced` and fails if any prohibited field
name occurs. The prohibited fields are exactly:
    message, targetText, expectedCharacter, unicodeCodePoint, characterName, glyphLabel

The test is dependency-light (stdlib only). It reads event JSON Schemas and the
AsyncAPI definition from `contracts/` at runtime (nothing is hardcoded except the
downstream sample event and the fallback pipeline order). PyYAML is used to derive the
pipeline ordering when available; otherwise a documented fallback ordering is used.

Run standalone:
    python tests/anti-chealing/test_prohibited_fields.py
Or via pytest:
    pytest tests/anti-cheating/test_prohibited_fields.py
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "contracts"
SCHEMA_DIR = CONTRACTS / "events"
ASYNCAPI_FILE = CONTRACTS / "asyncapi" / "domain-events.yaml"

PROHIBITED_FIELDS = {
    "message",
    "targetText",
    "expectedCharacter",
    "unicodeCodePoint",
    "characterName",
    "glyphLabel",
}

BOUNDARY_EVENT = "GlyphBlueprintProduced"

# Fallback pipeline order (message name -> schema file) used when the AsyncAPI
# spec cannot be parsed. Mirrors contracts/asyncapi/domain-events.yaml.
FALLBACK_PIPELINE = [
    ("GlyphBlueprintProduced", "glyph-blueprint-produced.v1.schema.json"),
    ("GeometryExpanded", "geometry-expanded.v1.schema.json"),
    ("VectorNormalized", "vector-normalized.v1.schema.json"),
    ("GlyphRasterized", "glyph-rasterized.v1.schema.json"),
    ("PhraseCompositionScheduled", "phrase-composition-scheduled.v1.schema.json"),
    ("PhraseComposed", "phrase-composed.v1.schema.json"),
    ("OcrImagePrepared", "ocr-image-prepared.v1.schema.json"),
    ("OcrObservationsProduced", "ocr-observations-produced.v1.schema.json"),
    ("SymbolAdjudicated", "symbol-adjudicated.v1.schema.json"),
    ("QualityRetry", "quality-retry.v1.schema.json"),
    ("PhraseAssembled", "phrase-assembled.v1.schema.json"),
    ("RunCompleted", "run-completed.v1.schema.json"),
    ("DeadLetter", "dead-letter.v1.schema.json"),
]

# A downstream event sample that MUST NOT contain any prohibited field.
# Shaped like a GeometryExpanded / VectorNormalized style event.
CLEAN_DOWNSTREAM_SAMPLE = {
    "specversion": "1.0",
    "id": "01H8EXAMPLEGOOD00000000001",
    "source": "geometry-engine",
    "type": "rg.geometry-expanded.v1",
    "subject": "runs/01H8EXAMPLE00000000000001/glyphs/01H8EXAMPLE00000000000002",
    "time": "2026-08-04T10:45:15.000Z",
    "datacontenttype": "application/json",
    "data": {
        "runId": "01H8EXAMPLE00000000000001",
        "glyphInstanceId": "01H8EXAMPLE00000000000002",
        "position": 0,
        "attempt": 1,
        "geometry": {
            "kind": "DRAWABLE_GEOMETRY",
            "boundingBox": {"xMin": 0.0, "yMin": 0.0, "xMax": 0.0, "yMax": 7.0},
            "advanceWidth": 0.5,
            "totalLength": 7.0,
            "segmentCount": 1,
            "geometrySha256": "a1b2c3d4e5f6",
        },
    },
}

FAILURES = []


def fail(msg):
    FAILURES.append(msg)


def collect_prohibited_in_object(obj):
    """Recursively collect any prohibited field NAMES present as keys in `obj`."""
    found = set()
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in PROHIBITED_FIELDS:
                found.add(key)
            found |= collect_prohibited_in_object(value)
    elif isinstance(obj, list):
        for item in obj:
            found |= collect_prohibited_in_object(item)
    return found


def collect_property_names(schema):
    """Recursively collect all property NAMES declared by a JSON Schema.

    Walks `properties`, nested object schemas, `patternProperties`,
    `additionalProperties` (when it is a schema object), and `items`.
    """
    found = set()
    if not isinstance(schema, dict):
        return found
    props = schema.get("properties")
    if isinstance(props, dict):
        for name, sub in props.items():
            found.add(name)
            found |= collect_property_names(sub)
    pattern_props = schema.get("patternProperties")
    if isinstance(pattern_props, dict):
        for sub in pattern_props.values():
            found |= collect_property_names(sub)
    additional = schema.get("additionalProperties")
    if isinstance(additional, dict):
        # A schema object: scan it (best-effort, since keys are not statically known).
        found |= collect_property_names(additional)
    items = schema.get("items")
    if isinstance(items, dict):
        found |= collect_property_names(items)
    return found


def load_pipeline_order():
    """Return ordered list of (message_name, schema_filename) after reading AsyncAPI.

    Falls back to FALLBACK_PIPELINE when PyYAML or the AsyncAPI file is unavailable.
    """
    try:
        import yaml  # noqa: F401
    except ImportError:
        print("[note] PyYAML not available; using hardcoded fallback pipeline order.")
        return list(FALLBACK_PIPELINE)
    if not ASYNCAPI_FILE.exists():
        print("[note] AsyncAPI spec missing; using hardcoded fallback pipeline order.")
        return list(FALLBACK_PIPELINE)
    try:
        with open(ASYNCAPI_FILE) as f:
            spec = yaml.safe_load(f)
        messages = spec.get("components", {}).get("messages", {})
        pipeline = []
        for name, body in messages.items():
            ref = (body or {}).get("payload", {}).get("$ref", "")
            filename = ref.rsplit("/", 1)[-1]
            pipeline.append((name, filename))
        if pipeline:
            return pipeline
        print("[note] AsyncAPI had no message order; using fallback pipeline order.")
        return list(FALLBACK_PIPELINE)
    except Exception as e:  # pragma: no cover - defensive
        print(f"[note] Could not parse AsyncAPI ({e}); using fallback pipeline order.")
        return list(FALLBACK_PIPELINE)


def load_schema(filename):
    path = SCHEMA_DIR / filename
    if not path.exists():
        return None
    with open(path) as f:
        return json.load(f)


def test_downstream_schemas_have_no_prohibited_fields():
    """Requirement 1: every event schema after GlyphBlueprintProduced is clean."""
    pipeline = load_pipeline_order()

    if BOUNDARY_EVENT not in {name for name, _ in pipeline}:
        fail(f"Boundary event '{BOUNDARY_EVENT}' not found in pipeline order.")

    boundary_index = next(
        i for i, (name, _) in enumerate(pipeline) if name == BOUNDARY_EVENT
    )
    downstream = pipeline[boundary_index + 1:]

    if not downstream:
        fail("No downstream events found after the boundary event.")

    for name, filename in downstream:
        schema = load_schema(filename)
        if schema is None:
            fail(f"Downstream schema '{filename}' (event {name}) is missing.")
            continue
        prop_names = collect_property_names(schema)
        offenders = sorted(prop_names & PROHIBITED_FIELDS)
        if offenders:
            fail(
                f"PROHIBITED FIELD: downstream event '{name}' ({filename}) declares "
                f"prohibited field(s): {', '.join(offenders)}"
            )
        else:
            print(f"  [ ok ] downstream event '{name}' has no prohibited fields")


def test_validator_accepts_clean_and_rejects_dirty_sample():
    """Requirement 2: the validator accepts a clean downstream sample and rejects a dirty one."""
    clean_offenders = collect_prohibited_in_object(CLEAN_DOWNSTREAM_SAMPLE)
    if clean_offenders:
        fail(
            f"Test fixture error: clean downstream sample unexpectedly contains "
            f"prohibited field(s): {', '.join(sorted(clean_offenders))}"
        )
    else:
        print("  [ ok ] validator accepts clean downstream sample")

    dirty = json.loads(json.dumps(CLEAN_DOWNSTREAM_SAMPLE))
    dirty["data"]["targetText"] = "HELLO"
    dirty_offenders = collect_prohibited_in_object(dirty)
    if "targetText" not in dirty_offenders:
        fail("Validator failed to reject a downstream sample containing 'targetText'")
    else:
        print(
            "  [ ok ] validator rejects downstream sample with 'targetText' "
            f"(detected: {', '.join(sorted(dirty_offenders))})"
        )


def main():
    print("Anti-cheating test: prohibited fields must be absent after glyph planning\n")
    test_downstream_schemas_have_no_prohibited_fields()
    test_validator_accepts_clean_and_rejects_dirty_sample()

    if FAILURES:
        print(f"\n{len(FAILURES)} failure(s):")
        for f in FAILURES:
            print(f"  FAIL: {f}")
        sys.exit(1)
    print("\nAll anti-cheating checks passed.")
    sys.exit(0)


if __name__ == "__main__":
    main()
