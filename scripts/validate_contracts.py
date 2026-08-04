#!/usr/bin/env python3
"""Contract generation and validation for Milestone 1.

Usage:
  make contracts      # validate all contract files parse correctly
  make contract-test  # run full contract tests including prohibited-field checks

Uses the project venv Python with jsonschema and pyyaml installed.
"""

import json
import sys
from pathlib import Path

try:
    import yaml
    from jsonschema import Draft202012Validator
except ImportError:
    print("ERROR: jsonschema or pyyaml not installed", file=sys.stderr)
    print("Install with:  pip install jsonschema pyyaml", file=sys.stderr)
    sys.exit(1)

ROOT = Path(__file__).resolve().parents[1]
CONTRACTS = ROOT / "contracts"
SCHEMA_DIR = CONTRACTS / "events"
OPENAPI_FILE = CONTRACTS / "openapi" / "rghello.yaml"
ASYNCAPI_FILE = CONTRACTS / "asyncapi" / "domain-events.yaml"
PROTO_FILE = CONTRACTS / "proto" / "rasterizer" / "v1" / "rasterizer.proto"
WSDL_FILE = CONTRACTS / "soap" / "glyph-catalog.wsdl"
XSD_FILE = CONTRACTS / "soap" / "glyph-catalog.xsd"

PROHIBITED_FIELDS = {
    "message",
    "targetText",
    "expectedCharacter",
    "unicodeCodePoint",
    "characterName",
    "glyphLabel",
}

ERRORS = []


def check(condition, msg):
    if not condition:
        ERRORS.append(msg)
        return False
    return True


def validate_schemas_parse():
    """Validate that every JSON Schema file parses correctly."""
    schemas = sorted(SCHEMA_DIR.glob("*.schema.json"))
    check(len(schemas) > 0, "No JSON Schema files found in contracts/events/")

    registry = {}
    schema_ids = set()
    for schema_path in schemas:
        try:
            with open(schema_path) as f:
                schema = json.load(f)
            schema_id = schema.get("$id", str(schema_path))
            schema_ids.add(schema_id)
            registry[schema_id] = schema_path
            Draft202012Validator.check_schema(schema)
        except json.JSONDecodeError as e:
            check(False, f"Schema {schema_path.name} is not valid JSON: {e}")
        except Exception as e:
            check(False, f"Schema {schema_path.name} is not valid JSON Schema: {e}")

    check(len(schemas) == len(schema_ids), "Duplicate schema $id values")
    return schemas, registry


def validate_examples(schemas):
    """Validate every example file against its corresponding schema."""
    example_dir = CONTRACTS / "examples"
    examples = sorted(example_dir.glob("*.example.json"))
    check(len(examples) > 0, "No example files found in contracts/examples/")

    for example_path in examples:
        try:
            with open(example_path) as f:
                example = json.load(f)
        except json.JSONDecodeError as e:
            check(False, f"Example {example_path.name} is not valid JSON: {e}")
            continue

        schema_name = example_path.name.replace(".example.json", ".schema.json")
        schema_path = SCHEMA_DIR / schema_name

        if schema_path not in schemas:
            # Check if it's an example without a corresponding schema (like prohibited fields)
            if "prohibited" in example_path.name:
                continue
            check(False, f"Example {example_path.name} has no matching schema {schema_name}")
            continue

        try:
            with open(schema_path) as f:
                schema = json.load(f)
        except Exception:
            continue

        validator = Draft202012Validator(schema)
        errors = sorted(validator.iter_errors(example["data"] if "data" in example else example),
                       key=lambda e: e.path)
        if errors:
            for error in errors:
                check(False,
                      f"Example {example_path.name} validation error: {error.message} at path {list(error.path)}")


def validate_openapi():
    """Validate OpenAPI spec parses."""
    if not check(OPENAPI_FILE.exists(), f"OpenAPI spec missing at {OPENAPI_FILE}"):
        return
    try:
        with open(OPENAPI_FILE) as f:
            spec = yaml.safe_load(f)
        check(spec.get("openapi", "").startswith("3."), f"OpenAPI version not 3.x: {spec.get('openapi')}")
        check("info" in spec, "OpenAPI spec missing 'info'")
        check("paths" in spec, "OpenAPI spec missing 'paths'")
    except yaml.YAMLError as e:
        check(False, f"OpenAPI spec is not valid YAML: {e}")


def validate_asyncapi():
    """Validate AsyncAPI spec parses."""
    if not check(ASYNCAPI_FILE.exists(), f"AsyncAPI spec missing at {ASYNCAPI_FILE}"):
        return
    try:
        with open(ASYNCAPI_FILE) as f:
            spec = yaml.safe_load(f)
        check(spec.get("asyncapi", "").startswith("2."), f"AsyncAPI version not 2.x: {spec.get('asyncapi')}")
        check("channels" in spec, "AsyncAPI spec missing 'channels'")
    except yaml.YAMLError as e:
        check(False, f"AsyncAPI spec is not valid YAML: {e}")


def validate_prohibited_fields():
    """Scan all event schemas for prohibited field names (section 7.4, 27.3).

    After glyph planning, events must not contain fields that could leak
    the expected plaintext to downstream workers.
    """
    schemas = sorted(SCHEMA_DIR.glob("*.schema.json"))
    for schema_path in schemas:
        with open(schema_path) as f:
            schema = json.load(f)

        found_fields = set()
        def scan_properties(obj):
            if isinstance(obj, dict):
                if "properties" in obj and isinstance(obj["properties"], dict):
                    for prop_name in obj["properties"]:
                        found_fields.add(prop_name)
                for v in obj.values():
                    scan_properties(v)
            elif isinstance(obj, list):
                for item in obj:
                    scan_properties(item)

        scan_properties(schema)
        for field in PROHIBITED_FIELDS:
            if field in found_fields:
                check(False,
                      f"PROHIBITED FIELD: Schema {schema_path.name} contains prohibited field '{field}'")

    example_dir = CONTRACTS / "examples"
    for example_path in example_dir.glob("*.example.json"):
        with open(example_path) as f:
            example = json.load(f)

        found_fields = set()
        def scan_keys(obj):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    found_fields.add(k)
                    scan_keys(v)
            elif isinstance(obj, list):
                for item in obj:
                    scan_keys(item)

        scan_keys(example)
        for field in PROHIBITED_FIELDS:
            if field in found_fields:
                check(False,
                      f"PROHIBITED FIELD: Example {example_path.name} contains prohibited field '{field}'")

    # Section 7.4: test that deliberately sends prohibited fields is detected
    test_event_path = ROOT / "tests" / "contract" / "prohibited_fields_test_event.json"
    if test_event_path.exists():
        with open(test_event_path) as f:
            test_event = json.load(f)
        found_prohibited = set()

        def scan_keys_test(obj):
            if isinstance(obj, dict):
                for k, v in obj.items():
                    if k in PROHIBITED_FIELDS:
                        found_prohibited.add(k)
                    scan_keys_test(v)
            elif isinstance(obj, list):
                for item in obj:
                    scan_keys_test(item)

        scan_keys_test(test_event)
        check(len(found_prohibited) > 0,
              "Prohibited-field test event must contain at least one prohibited field")
        for field in found_prohibited:
            print(f"  [ ok ] Prohibited field '{field}' correctly detected in test event")


def validate_protobuf():
    """Validate protobuf file exists and has expected service."""
    if not check(PROTO_FILE.exists(), f"Proto file missing at {PROTO_FILE}"):
        return
    content = PROTO_FILE.read_text()
    check("service Rasterizer" in content, "Protobuf missing Rasterizer service")
    check("rpc RenderGlyph" in content, "Protobuf missing RenderGlyph RPC")


def validate_wsdl_xsd():
    """Validate WSDL and XSD files exist and are valid XML."""
    for label, path in [("WSDL", WSDL_FILE), ("XSD", XSD_FILE)]:
        if not check(path.exists(), f"{label} file missing at {path}"):
            continue
        content = path.read_text()
        check(content.strip().startswith("<?xml"), f"{label} does not start with XML declaration")

    if XSD_FILE.exists():
        content = XSD_FILE.read_text()
        check("PlanPhraseRequest" in content, "XSD missing PlanPhraseRequest")
        check("GetAlternateBlueprint" in content, "XSD missing GetAlternateBlueprint")

    if WSDL_FILE.exists():
        content = WSDL_FILE.read_text()
        check("PlanPhrase" in content, "WSDL missing PlanPhrase operation")
        check("GetAlternateBlueprint" in content, "WSDL missing GetAlternateBlueprint operation")


def main():
    args = sys.argv[1:]
    contracts_only = "--contracts-only" in args

    print("Validating contract schemas...")
    schemas, registry = validate_schemas_parse()

    print("Validating OpenAPI spec...")
    validate_openapi()

    print("Validating AsyncAPI spec...")
    validate_asyncapi()

    print("Validating Protobuf spec...")
    validate_protobuf()

    print("Validating WSDL/XSD...")
    validate_wsdl_xsd()

    if contracts_only:
        if ERRORS:
            print(f"\n{len(ERRORS)} error(s) found:")
            for e in ERRORS:
                print(f"  FAIL: {e}")
            sys.exit(1)
        else:
            print("\nAll contract files parse correctly.")
            sys.exit(0)

    print("Validating examples against schemas...")
    validate_examples(schemas)

    print("Scanning for prohibited fields...")
    validate_prohibited_fields()

    if ERRORS:
        print(f"\n{len(ERRORS)} error(s) found:")
        for e in ERRORS:
            print(f"  FAIL: {e}")
        sys.exit(1)
    else:
        print("\nAll contract checks passed.")
        sys.exit(0)


if __name__ == "__main__":
    main()
