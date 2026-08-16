# Anti-Cheating: Prohibited Downstream Fields Test

This test enforces architecture section 7.4 ("Static enforcement"): it scans every
event JSON Schema that appears *after* `GlyphBlueprintProduced` in the pipeline
(`contracts/asyncapi/domain-events.yaml`, or a documented fallback order) and fails if
any prohibited plaintext field name — `message`, `targetText`, `expectedCharacter`,
`unicodeCodePoint`, `characterName`, `glyphLabel` — is declared in its properties
(recursively, including nested objects and `additionalProperties`). It also asserts the
validator accepts a clean downstream sample yet rejects one injected with a prohibited
field (e.g. `targetText`). The test is stdlib-only and reads `contracts/` at runtime.

Run standalone:

```sh
python tests/anti-cheating/test_prohibited_fields.py
```

Or via pytest:

```sh
pytest tests/anti-cheating/test_prohibited_fields.py
```

It exits non-zero on failure. PyYAML is used to derive the pipeline order when present;
otherwise a hardcoded fallback order is used and noted.
