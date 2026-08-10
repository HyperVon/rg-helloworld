# Artifact Lineage

Every primary transformation artifact in the pipeline records its input
artifact IDs, SHA-256 hash, maturity rank, and byte count. The orchestrator
persists lineage records in PostgreSQL and stores the binary payload in MinIO.

## Maturity ranks

| Rank | Artifact | Producer |
| ---: | --- | --- |
| 0 | Run request | CLI |
| 10 | Glyph blueprint | Java glyph catalog |
| 20 | Raw geometric segments | C++ geometry engine |
| 30 | Normalized vector glyph | Go vector normalizer |
| 40 | Rasterized glyph image | C# rasterizer |
| 50 | Composed phrase image | Python image pipeline |
| 60 | OCR-prepared phrase image | Python image pipeline |
| 70 | Raw OCR observations | Node OCR worker |
| 80 | Adjudicated symbols | Ruby adjudicator |
| 90 | Assembled UTF-8 phrase | Rust phrase assembler |
| 100 | Validated console result | Go CLI |

## PostgreSQL schema

```sql
CREATE TABLE artifacts (
    artifact_id UUID PRIMARY KEY,
    run_id UUID NOT NULL REFERENCES runs(run_id),
    step_id UUID NOT NULL REFERENCES run_steps(step_id),
    glyph_instance_id UUID,
    artifact_type VARCHAR(80) NOT NULL,
    maturity_rank INTEGER NOT NULL,
    object_key TEXT NOT NULL,
    content_type VARCHAR(120) NOT NULL,
    sha256 CHAR(64) NOT NULL,
    byte_count BIGINT NOT NULL,
    metadata JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL,
    UNIQUE(run_id, object_key)
);

CREATE TABLE artifact_lineage (
    output_artifact_id UUID NOT NULL REFERENCES artifacts(artifact_id),
    input_artifact_id UUID NOT NULL REFERENCES artifacts(artifact_id),
    PRIMARY KEY(output_artifact_id, input_artifact_id)
);
```

## MinIO layout

Bucket: `rube-goldberg-artifacts`

Object keys are run-scoped and opaque. The artifact inspector and CLI never
expose the requested plaintext through artifact metadata.

## Integrity rules

- Every primary transformation event must reference at least one input artifact
  and produce at least one output artifact.
- Maturity ranks must strictly increase. The orchestrator rejects events that
  claim to move backward or remain at the same rank.
- Every output artifact records the SHA-256 hash of each input and output.
- Large payloads stay in MinIO; Kafka carries only references.
