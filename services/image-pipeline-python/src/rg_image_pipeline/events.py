from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass, field
from typing import Any

PROHIBITED_FIELDS = {
    "message",
    "targetText",
    "expectedCharacter",
    "unicodeCodePoint",
    "characterName",
    "glyphLabel",
}


@dataclass
class CloudEvent:
    specversion: str = "1.0"
    id: str = ""
    source: str = ""
    type: str = ""
    subject: str = ""
    time: str = ""
    datacontenttype: str = "application/json"
    traceparent: str = ""
    tracestate: str = ""
    correlationid: str = ""
    causationid: str = ""
    data: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "specversion": self.specversion,
            "id": self.id,
            "source": self.source,
            "type": self.type,
            "subject": self.subject,
            "time": self.time,
            "datacontenttype": self.datacontenttype,
            "traceparent": self.traceparent,
            "tracestate": self.tracestate,
            "correlationid": self.correlationid,
            "causationid": self.causationid,
            "data": self.data,
        }

    def to_bytes(self) -> bytes:
        return json.dumps(self.to_dict(), sort_keys=True).encode()


def deterministic_event_id(run_id: str, step: str, attempt: int, data_hash: str) -> str:
    payload = json.dumps(
        {"runId": run_id, "step": step, "attempt": attempt, "dataHash": data_hash},
        sort_keys=True,
    )
    return "01H8" + hashlib.sha256(payload.encode()).hexdigest()[:20]


def validate_no_prohibited_fields(data: dict[str, Any]) -> bool:
    found = set()

    def scan(obj: Any) -> None:
        if isinstance(obj, dict):
            for k, v in obj.items():
                found.add(k)
                scan(v)
        elif isinstance(obj, list):
            for item in obj:
                scan(item)

    scan(data)
    prohibited_found = found & PROHIBITED_FIELDS
    return len(prohibited_found) == 0


def build_operation_id(run_id: str, step_name: str, attempt: int, input_hash: str) -> str:
    return hashlib.sha256(f"{run_id}:{step_name}:{attempt}:{input_hash}".encode()).hexdigest()
