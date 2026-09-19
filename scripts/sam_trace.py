#!/usr/bin/env python3
"""Local, report-only operational trace projection for SE-397 F4."""
from __future__ import annotations

from datetime import datetime
import hashlib
import json
import math
from pathlib import Path
import re
import stat
import sys

from sam_model import GOLDEN_FLOWS, SamValidationError, _read_json, _validate_model


_HEX32 = re.compile(r"^[0-9a-f]{32}$")
_HEX16 = re.compile(r"^[0-9a-f]{16}$")
_SHA = re.compile(r"^[0-9a-f]{64}$")
_IDENTIFIER = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$")
_TIMESTAMP = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
_EVENTS = {"operation.started", "operation.segment", "operation.completed"}
_PHASES = {"INTENT", "CONTEXT", "ROUTING", "GOVERNANCE", "EXECUTION", "EVIDENCE", "RESULT"}
_OUTCOMES = {"success", "failure", "partial", "blocked", "unknown"}
_BASE_FIELDS = {
    "schema", "ts", "event", "trace_id", "span_id", "parent_span_id",
    "session_id", "operation_id", "request_id", "flow_id",
    "model_revision", "frontend_id", "sequence",
}
_REPORT_LIMITATIONS = [
    "LOCAL_OBSERVATIONS_ONLY", "NO_CAUSAL_INFERENCE", "NO_AUTHORITY_EFFECT",
    "PARTIAL_FRONTEND_COVERAGE", "SELF_REPORTED_LOCAL_EVENTS",
]


def _duplicates(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate key")
        result[key] = value
    return result


def _safe_file(root: Path, path: Path) -> Path:
    root = root.resolve()
    candidate = path if path.is_absolute() else root / path
    try:
        metadata = candidate.lstat()
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, ValueError) as exc:
        raise SamValidationError("INVALID_OPERATION_TRACE", str(path)) from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode) \
            or metadata.st_size > 16 * 1024 * 1024:
        raise SamValidationError("INVALID_OPERATION_TRACE", str(path))
    return resolved


def _safe_directory(root: Path, path: Path) -> Path:
    root = root.resolve()
    candidate = path if path.is_absolute() else root / path
    try:
        metadata = candidate.lstat()
        resolved = candidate.resolve(strict=True)
        resolved.relative_to(root)
    except (OSError, ValueError) as exc:
        raise SamValidationError("INVALID_OPERATION_TRACE", str(path)) from exc
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISDIR(metadata.st_mode):
        raise SamValidationError("INVALID_OPERATION_TRACE", str(path))
    return resolved


def _parse_timestamp(value: object) -> datetime:
    if not isinstance(value, str) or not _TIMESTAMP.fullmatch(value):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/ts")
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def validate_operation_event(value: object) -> dict:
    """Validate one strict F4 event independently of a SAM revision."""
    if not isinstance(value, dict) or value.get("event") not in _EVENTS:
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/event")
    if set(value) == {"schema", "ts", "event"}:
        if value.get("schema") != "savia.event/1.0":
            raise SamValidationError("INVALID_OPERATION_TRACE", "$/schema")
        _parse_timestamp(value.get("ts"))
        return value

    event = value["event"]
    event_fields = {
        "operation.started": _BASE_FIELDS | {"outcome"},
        "operation.segment": _BASE_FIELDS | {
            "phase", "architecture_node_id", "duration_ms", "evidence_ref",
        },
        "operation.completed": _BASE_FIELDS | {"duration_ms", "outcome"},
    }[event]
    required = event_fields - {"parent_span_id", "session_id"}
    if set(value) - event_fields or required - set(value):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$")
    if value["schema"] != "savia.event/1.0":
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/schema")
    _parse_timestamp(value["ts"])
    if not isinstance(value["trace_id"], str) or not _HEX32.fullmatch(value["trace_id"]):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/trace_id")
    if not isinstance(value["span_id"], str) or not _HEX16.fullmatch(value["span_id"]):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/span_id")
    if "parent_span_id" in value and (
            not isinstance(value["parent_span_id"], str)
            or not _HEX16.fullmatch(value["parent_span_id"])):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/parent_span_id")
    if not isinstance(value["operation_id"], str) or not _HEX32.fullmatch(value["operation_id"]):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/operation_id")
    if value["request_id"] is not None and (
            not isinstance(value["request_id"], str)
            or not _IDENTIFIER.fullmatch(value["request_id"])):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/request_id")
    if value["flow_id"] not in GOLDEN_FLOWS:
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/flow_id")
    if not isinstance(value["model_revision"], str) or not _SHA.fullmatch(value["model_revision"]):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/model_revision")
    if not isinstance(value["frontend_id"], str) or not _IDENTIFIER.fullmatch(value["frontend_id"]) \
            or len(value["frontend_id"]) > 64:
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/frontend_id")
    if type(value["sequence"]) is not int or value["sequence"] < 0:
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/sequence")

    if event == "operation.started":
        if value["sequence"] != 0 or value["outcome"] != "unknown":
            raise SamValidationError("INVALID_OPERATION_TRACE", "$/sequence")
    elif event == "operation.segment":
        if value["sequence"] < 1 or value["phase"] not in _PHASES:
            raise SamValidationError("INVALID_OPERATION_TRACE", "$/phase")
        if not isinstance(value["architecture_node_id"], str) \
                or not _IDENTIFIER.fullmatch(value["architecture_node_id"]):
            raise SamValidationError("INVALID_OPERATION_TRACE", "$/architecture_node_id")
        if value["evidence_ref"] is not None and (
                not isinstance(value["evidence_ref"], str)
                or value["evidence_ref"].startswith("/")
                or ".." in Path(value["evidence_ref"]).parts):
            raise SamValidationError("INVALID_OPERATION_TRACE", "$/evidence_ref")
    else:
        if value["sequence"] < 1 or value["outcome"] not in _OUTCOMES \
                or value["outcome"] == "unknown":
            raise SamValidationError("INVALID_OPERATION_TRACE", "$/outcome")
    if event != "operation.started" and (
            type(value["duration_ms"]) is not int or value["duration_ms"] < 0):
        raise SamValidationError("INVALID_OPERATION_TRACE", "$/duration_ms")
    return value


def _read_events(root: Path, path: Path) -> tuple[list[dict], int]:
    source = _safe_file(root, path)
    events = []
    redacted = 0
    try:
        with source.open("rb") as stream:
            for number, raw in enumerate(stream, 1):
                if len(raw) > 1024 * 1024:
                    raise SamValidationError("INVALID_OPERATION_TRACE", f"{path}:{number}")
                try:
                    value = json.loads(raw.decode("utf-8"), object_pairs_hook=_duplicates)
                except (UnicodeError, json.JSONDecodeError, ValueError) as exc:
                    raise SamValidationError(
                        "INVALID_OPERATION_TRACE", f"{path}:{number}"
                    ) from exc
                if not isinstance(value, dict) or value.get("event") not in _EVENTS:
                    continue
                validated = validate_operation_event(value)
                if set(validated) == {"schema", "ts", "event"}:
                    redacted += 1
                else:
                    events.append(validated)
    except OSError as exc:
        raise SamValidationError("INVALID_OPERATION_TRACE", str(path)) from exc
    return events, redacted


def _receipt_correlation(root: Path, receipts_path: Path | None,
                         operation: dict, segments: list[dict]) -> tuple[str, set[str]]:
    references = sorted({
        item["evidence_ref"] for item in segments if item["evidence_ref"] is not None
    })
    if not references:
        return "NOT_PROVIDED", set()
    if len(references) != 1:
        return "CONFLICT", {"RECEIPT_CONFLICT"}
    if receipts_path is None:
        return "NOT_FOUND", {"RECEIPT_NOT_FOUND"}
    receipts = _safe_directory(root, receipts_path)
    reference = Path(references[0])
    try:
        target = _safe_file(root, reference)
        target.relative_to(receipts)
    except (SamValidationError, ValueError):
        return "NOT_FOUND", {"RECEIPT_NOT_FOUND"}
    if target.suffix != ".json":
        return "INVALID", {"RECEIPT_INVALID"}
    try:
        value = json.loads(
            target.read_text(encoding="utf-8"), object_pairs_hook=_duplicates
        )
        contract_dir = str(Path(__file__).resolve().parent / "dual-cli")
        sys.path.insert(0, contract_dir)
        try:
            from contracts import receipt as validate_receipt
            validate_receipt(value)
        finally:
            sys.path.pop(0)
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError, ImportError):
        return "INVALID", {"RECEIPT_INVALID"}
    execution = value.get("execution")
    outcome_map = {
        "succeeded": "success", "failed": "failure", "blocked": "blocked",
        "cancelled": "unknown", "unknown": "unknown",
    }
    if operation["request_id"] is None or value["request_id"] != operation["request_id"] \
            or value["context"]["frontend_id"] != operation["frontend_id"] \
            or execution is None \
            or outcome_map.get(execution["state"]) != operation["outcome"]:
        return "CONFLICT", {"RECEIPT_CONFLICT"}
    return "VALID_CORRELATED", set()


def build_trace(root: Path, events_path: Path, receipts_path: Path | None = None) -> dict:
    """Build a deterministic report from local F4 events."""
    root = root.resolve()
    model = _read_json(root / ".scm/sam.json", "INVALID_MODEL")
    _validate_model(model, root, verify_sources=False)
    node_ids = {node["id"] for node in model["nodes"]}
    events, redacted = _read_events(root, events_path)
    grouped: dict[str, list[dict]] = {}
    for event in events:
        grouped.setdefault(event["operation_id"], []).append(event)

    operations = []
    for operation_id in sorted(grouped):
        current = sorted(grouped[operation_id], key=lambda item: item["sequence"])
        first = current[0]
        starts = [item for item in current if item["event"] == "operation.started"]
        completions = [item for item in current if item["event"] == "operation.completed"]
        segments = [item for item in current if item["event"] == "operation.segment"]
        identity = (
            "request_id", "trace_id", "flow_id", "model_revision", "frontend_id"
        )
        gaps = set()
        if not starts:
            gaps.add("MISSING_START")
        elif len(starts) > 1:
            gaps.add("IDENTITY_CONFLICT")
        if not completions:
            gaps.add("MISSING_COMPLETION")
        elif len(completions) > 1:
            gaps.add("IDENTITY_CONFLICT")
        if not segments:
            gaps.add("MISSING_SEGMENT")
        sequences = [item["sequence"] for item in current]
        if sequences != list(range(max(sequences, default=-1) + 1)):
            gaps.add("SEQUENCE_GAP")
        if not all(item[key] == first[key] for item in current for key in identity):
            gaps.add("IDENTITY_CONFLICT")
        if any(item["architecture_node_id"] not in node_ids for item in segments):
            gaps.add("UNKNOWN_ARCHITECTURE_NODE")
        if first["model_revision"] != model["model_revision"]:
            gaps.add("STALE_MODEL_REVISION")
        if len(completions) == 1 and sum(
                item["duration_ms"] for item in segments
        ) > completions[0]["duration_ms"]:
            gaps.add("DURATION_CONFLICT")
        if any(
            _parse_timestamp(left["ts"]) > _parse_timestamp(right["ts"])
            for left, right in zip(current, current[1:])
        ):
            gaps.add("TIME_ORDER_CONFLICT")
        public_segments = [
            {
                "sequence": item["sequence"], "phase": item["phase"],
                "architecture_node_id": item["architecture_node_id"],
                "duration_ms": item["duration_ms"],
                "evidence_ref": item["evidence_ref"],
            }
            for item in segments
        ]
        operation = {
            "operation_id": operation_id,
            "request_id": first["request_id"],
            "trace_id": first["trace_id"],
            "flow_id": first["flow_id"],
            "frontend_id": first["frontend_id"],
            "outcome": completions[0]["outcome"] if len(completions) == 1 else "unknown",
            "duration_ms": completions[0]["duration_ms"] if len(completions) == 1 else 0,
            "architecture_path": [item["architecture_node_id"] for item in segments],
            "segments": public_segments,
        }
        receipt_status, receipt_gaps = _receipt_correlation(
            root, receipts_path, operation, segments
        )
        gaps.update(receipt_gaps)
        operation.update({
            "status": "COMPLETE" if not gaps else "PARTIAL",
            "receipt_status": receipt_status,
            "gaps": sorted(gaps),
        })
        operations.append(operation)

    complete_count = sum(item["status"] == "COMPLETE" for item in operations)
    return {
        "schema_version": 1,
        "report": "operational-trace",
        "model_revision": model["model_revision"],
        "summary": {
            "operations": len(operations), "complete": complete_count,
            "partial": len(operations) - complete_count,
            "redacted_unlinkable": redacted,
        },
        "operations": operations,
        "limitations": _REPORT_LIMITATIONS,
    }


def _distribution(key: str, name: str, values: list[int]) -> dict:
    ordered = sorted(values)

    def percentile(fraction: float) -> int:
        return ordered[max(0, math.ceil(fraction * len(ordered)) - 1)]

    return {
        key: name,
        "count": len(ordered),
        "min_ms": ordered[0],
        "p50_ms": percentile(0.50),
        "p95_ms": percentile(0.95),
        "p99_ms": percentile(0.99),
        "max_ms": ordered[-1],
    }


def build_baseline(root: Path, events_path: Path,
                   receipts_path: Path | None = None) -> dict:
    """Aggregate complete observations without creating an SLO or verdict."""
    trace = build_trace(root, events_path, receipts_path)
    complete = [item for item in trace["operations"] if item["status"] == "COMPLETE"]
    if not complete:
        raise SamValidationError(
            "INSUFFICIENT_OPERATIONAL_EVIDENCE", str(events_path)
        )
    flow_values: dict[str, list[int]] = {}
    phase_values: dict[str, list[int]] = {}
    semantic = []
    for operation in complete:
        flow_values.setdefault(operation["flow_id"], []).append(operation["duration_ms"])
        for segment in operation["segments"]:
            phase_values.setdefault(segment["phase"], []).append(segment["duration_ms"])
        semantic.append({
            "flow_id": operation["flow_id"],
            "frontend_id": operation["frontend_id"],
            "outcome": operation["outcome"],
            "segments": [
                {
                    "phase": item["phase"],
                    "architecture_node_id": item["architecture_node_id"],
                }
                for item in operation["segments"]
            ],
        })
    corpus = json.dumps(
        sorted(semantic, key=lambda item: json.dumps(item, sort_keys=True)),
        ensure_ascii=False, sort_keys=True, separators=(",", ":"),
    ).encode("utf-8")
    gaps = sorted({
        gap for operation in trace["operations"] for gap in operation["gaps"]
    })
    return {
        "schema_version": 1,
        "report": "operational-baseline",
        "model_revision": trace["model_revision"],
        "corpus_revision": hashlib.sha256(corpus).hexdigest(),
        "summary": {
            "operations": len(trace["operations"]),
            "complete": len(complete),
            "coverage": "PARTIAL",
        },
        "by_flow": [
            _distribution("flow_id", name, flow_values[name])
            for name in sorted(flow_values)
        ],
        "by_phase": [
            _distribution("phase", name, phase_values[name])
            for name in sorted(phase_values)
        ],
        "gaps": gaps,
        "limitations": [
            "CONTROLLED_LOCAL_CORPUS", "NO_PRODUCTION_SLO",
            "NO_CROSS_FRONTEND_EQUIVALENCE", "REPORT_ONLY",
        ],
    }
