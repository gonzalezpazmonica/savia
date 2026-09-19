"""SE-397 F4 behavioral tests for local operational traces."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

from jsonschema import Draft7Validator


ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/sam/valid"
TRACE_FIXTURE = ROOT / "tests/fixtures/sam/trace"


class SamTraceTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "repo"
        shutil.copytree(FIXTURE, self.root)
        self._git("init", "-q")
        self._git("config", "user.name", "SAM Trace Tests")
        self._git("config", "user.email", "sam-trace-tests@localhost")
        self._git("add", ".")
        self._git("commit", "-qm", "fixture")
        generated = self._cli("generate")
        self.assertEqual(0, generated.returncode, generated.stderr)
        self.model = json.loads((self.root / ".scm/sam.json").read_text())
        (self.root / "output").mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def _git(self, *args: str) -> None:
        subprocess.run(
            ["git", *args], cwd=self.root, check=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def _cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/sam.py"), *args,
             "--root", str(self.root)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def _write_events(self, events: list[dict]) -> Path:
        path = self.root / "output/events.jsonl"
        path.write_text("".join(json.dumps(item) + "\n" for item in events))
        return path

    def _complete_events(self, index: int, duration: int) -> list[dict]:
        digit = format(index + 1, "x")
        common = {
            "schema": "savia.event/1.0",
            "trace_id": digit * 32,
            "operation_id": format(index + 8, "x") * 32,
            "request_id": f"request-{index}",
            "flow_id": "flow:read",
            "model_revision": self.model["model_revision"],
            "frontend_id": "fixture",
        }
        return [
            dict(common, ts="2026-09-16T08:00:00Z", event="operation.started",
                 span_id="a" * 16, sequence=0, outcome="unknown"),
            dict(common, ts="2026-09-16T08:00:01Z", event="operation.segment",
                 span_id="b" * 16, sequence=1, phase="EXECUTION",
                 architecture_node_id="flow:read", duration_ms=duration,
                 evidence_ref=None),
            dict(common, ts="2026-09-16T08:00:02Z", event="operation.completed",
                 span_id="c" * 16, sequence=2, duration_ms=duration,
                 outcome="success"),
        ]

    def test_trace_projects_one_complete_read_operation(self):
        events = json.loads((TRACE_FIXTURE / "valid/read-events.json").read_text())
        for event in events:
            event["model_revision"] = self.model["model_revision"]
        path = self._write_events(events)

        result = self._cli("trace", "--events", str(path))

        self.assertEqual(0, result.returncode, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(
            {"operations": 1, "complete": 1, "partial": 0,
             "redacted_unlinkable": 0},
            report["summary"],
        )
        operation = report["operations"][0]
        self.assertEqual("COMPLETE", operation["status"])
        self.assertEqual(["flow:read"], operation["architecture_path"])
        self.assertEqual("NOT_PROVIDED", operation["receipt_status"])

    def test_trace_uses_valid_committed_model_when_worktree_sources_drift(self):
        events = self._complete_events(0, 5)
        path = self._write_events(events)
        source = self.root / "scripts/tool.sh"
        source.write_text(source.read_text() + "\n# uncommitted drift\n")

        result = self._cli("trace", "--events", str(path))

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(1, json.loads(result.stdout)["summary"]["complete"])

    def test_trace_keeps_incomplete_operation_with_exact_gaps(self):
        common = {
            "schema": "savia.event/1.0",
            "trace_id": "3" * 32,
            "operation_id": "4" * 32,
            "request_id": None,
            "flow_id": "flow:read",
            "model_revision": self.model["model_revision"],
            "frontend_id": "fixture",
        }
        path = self._write_events([
            dict(common, ts="2026-09-16T08:00:01Z", event="operation.segment",
                 span_id="d" * 16, sequence=2, phase="EXECUTION",
                 architecture_node_id="component:missing", duration_ms=3,
                 evidence_ref=None),
            dict(common, ts="2026-09-16T08:00:02Z", event="operation.completed",
                 span_id="e" * 16, sequence=3, duration_ms=4,
                 outcome="partial"),
        ])

        result = self._cli("trace", "--events", str(path))

        self.assertEqual(0, result.returncode, result.stderr)
        operation = json.loads(result.stdout)["operations"][0]
        self.assertEqual("PARTIAL", operation["status"])
        self.assertEqual(
            ["MISSING_START", "SEQUENCE_GAP", "UNKNOWN_ARCHITECTURE_NODE"],
            operation["gaps"],
        )

    def test_trace_reports_identity_time_duration_and_revision_conflicts(self):
        events = self._complete_events(0, 8)
        for event in events:
            event["model_revision"] = "0" * 64
        events[0]["ts"] = "2026-09-16T08:00:02Z"
        events[1]["ts"] = "2026-09-16T08:00:01Z"
        events[2]["duration_ms"] = 5
        events[2]["frontend_id"] = "conflicting-frontend"
        path = self._write_events(events)

        result = self._cli("trace", "--events", str(path))

        self.assertEqual(0, result.returncode, result.stderr)
        operation = json.loads(result.stdout)["operations"][0]
        self.assertEqual("PARTIAL", operation["status"])
        self.assertEqual(
            ["DURATION_CONFLICT", "IDENTITY_CONFLICT", "STALE_MODEL_REVISION",
             "TIME_ORDER_CONFLICT"],
            operation["gaps"],
        )

    def test_trace_output_is_identical_for_shuffled_lines(self):
        events = self._complete_events(0, 5) + self._complete_events(1, 8)
        ordered = self.root / "output/ordered.jsonl"
        shuffled = self.root / "output/shuffled.jsonl"
        ordered.write_text("".join(json.dumps(item) + "\n" for item in events))
        shuffled.write_text(
            "".join(json.dumps(item) + "\n" for item in reversed(events))
        )

        first = self._cli("trace", "--events", str(ordered))
        second = self._cli("trace", "--events", str(shuffled))

        self.assertEqual(0, first.returncode, first.stderr)
        self.assertEqual(0, second.returncode, second.stderr)
        self.assertEqual(first.stdout, second.stdout)

    def test_trace_rejects_malformed_and_duplicate_json_without_stdout(self):
        path = self.root / "output/invalid.jsonl"
        for payload in (
            "{not-json}\n",
            (TRACE_FIXTURE / "adversarial/duplicate-keys.jsonl").read_text(),
        ):
            with self.subTest(payload=payload):
                path.write_text(payload)
                result = self._cli("trace", "--events", str(path))
                self.assertEqual(2, result.returncode)
                self.assertEqual("", result.stdout)
                self.assertIn("INVALID_OPERATION_TRACE", result.stderr)

    def test_trace_rejects_unknown_f4_field_without_stdout(self):
        event = self._complete_events(0, 5)[0]
        event["unexpected"] = "not-allowed"
        path = self._write_events([event])

        result = self._cli("trace", "--events", str(path))

        self.assertEqual(2, result.returncode)
        self.assertEqual("", result.stdout)
        self.assertIn("INVALID_OPERATION_TRACE", result.stderr)

    def test_trace_rejects_oversized_lines_and_unsafe_paths(self):
        oversized = self.root / "output/oversized.jsonl"
        oversized.write_bytes(b"{" + b"x" * (1024 * 1024) + b"}\n")
        outside = Path(self.temp.name) / "outside.jsonl"
        outside.write_text("{}\n")
        symlink = self.root / "output/events-link.jsonl"
        symlink.symlink_to(outside)

        for path in (oversized, outside, symlink):
            with self.subTest(path=path):
                result = self._cli("trace", "--events", str(path))
                self.assertEqual(2, result.returncode)
                self.assertEqual("", result.stdout)
                self.assertIn("INVALID_OPERATION_TRACE", result.stderr)

    def test_baseline_uses_nearest_rank_percentiles(self):
        events = []
        for index, duration in enumerate([1, 2, 3, 4, 100]):
            events.extend(self._complete_events(index, duration))
        path = self._write_events(list(reversed(events)))

        result = self._cli("baseline", "--events", str(path))

        self.assertEqual(0, result.returncode, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual("operational-baseline", report["report"])
        self.assertEqual(
            {"flow_id": "flow:read", "count": 5, "min_ms": 1,
             "p50_ms": 3, "p95_ms": 100, "p99_ms": 100, "max_ms": 100},
            report["by_flow"][0],
        )
        self.assertRegex(report["corpus_revision"], r"^[0-9a-f]{64}$")

    def test_baseline_rejects_zero_complete_operations(self):
        common = {
            "schema": "savia.event/1.0", "ts": "2026-09-16T08:00:00Z",
            "event": "operation.started", "trace_id": "a" * 32,
            "span_id": "b" * 16, "operation_id": "c" * 32,
            "request_id": None, "flow_id": "flow:read",
            "model_revision": self.model["model_revision"],
            "frontend_id": "fixture", "sequence": 0, "outcome": "unknown",
        }
        path = self._write_events([common])

        result = self._cli("baseline", "--events", str(path))

        self.assertEqual(2, result.returncode)
        self.assertEqual("", result.stdout)
        self.assertIn("INSUFFICIENT_OPERATIONAL_EVIDENCE", result.stderr)

    def test_trace_correlates_a_valid_v2_receipt(self):
        events = self._complete_events(0, 5)
        events[1]["evidence_ref"] = "output/receipts/read.json"
        path = self._write_events(events)
        receipts = self.root / "output/receipts"
        receipts.mkdir()
        receipt = {
            "schema": 2,
            "context": {
                "schema": 2, "run_id": "run", "session_id": "session",
                "repo_id": "repo", "frontend_id": "fixture",
                "adapter_version": "v1", "policy_revision": "policy",
                "effective_config_hash": "config", "provider_id": None,
                "model_id": None, "model_revision": None,
                "inference_mode": "cli_managed", "domain_ids": ["core-local"],
                "authority_ceiling": "L2",
            },
            "request_id": "request-0", "event_id": "event",
            "decision_id": "decision", "decision": "proceed",
            "execution": {
                "request_id": "request-0", "state": "succeeded",
                "reason": "completed", "artifacts": [], "usage": None,
                "external_effect_observed": False,
            },
            "observation_refs": [], "human_gate_count": 0,
            "delegated_execution": True, "decision_authority": "human",
        }
        (receipts / "read.json").write_text(json.dumps(receipt) + "\n")

        result = self._cli(
            "trace", "--events", str(path), "--receipts", str(receipts)
        )

        self.assertEqual(0, result.returncode, result.stderr)
        operation = json.loads(result.stdout)["operations"][0]
        self.assertEqual("VALID_CORRELATED", operation["receipt_status"])
        self.assertEqual([], operation["gaps"])

    def test_receipt_absence_invalidity_and_conflict_remain_explicit(self):
        receipts = self.root / "output/receipts"
        receipts.mkdir()
        cases = (
            ("missing.json", None, "NOT_FOUND", "RECEIPT_NOT_FOUND"),
            (
                "v1.json",
                json.loads((TRACE_FIXTURE / "receipts/schema-v1.json").read_text()),
                "INVALID", "RECEIPT_INVALID",
            ),
            (
                "conflict.json",
                {
                    "schema": 2,
                    "context": {
                        "schema": 2, "run_id": "run", "session_id": "session",
                        "repo_id": "repo", "frontend_id": "other-frontend",
                        "adapter_version": "v1", "policy_revision": "policy",
                        "effective_config_hash": "config", "provider_id": None,
                        "model_id": None, "model_revision": None,
                        "inference_mode": "cli_managed", "domain_ids": ["core-local"],
                        "authority_ceiling": "L2",
                    },
                    "request_id": "request-0", "event_id": "event",
                    "decision_id": "decision", "decision": "proceed",
                    "execution": {
                        "request_id": "request-0", "state": "succeeded",
                        "reason": "completed", "artifacts": [], "usage": None,
                        "external_effect_observed": False,
                    },
                    "observation_refs": [], "human_gate_count": 0,
                    "delegated_execution": True, "decision_authority": "human",
                },
                "CONFLICT", "RECEIPT_CONFLICT",
            ),
        )
        for name, receipt, status, gap in cases:
            with self.subTest(name=name):
                if receipt is not None:
                    (receipts / name).write_text(json.dumps(receipt) + "\n")
                events = self._complete_events(0, 5)
                events[1]["evidence_ref"] = f"output/receipts/{name}"
                path = self._write_events(events)
                result = self._cli(
                    "trace", "--events", str(path),
                    "--receipts", str(receipts),
                )
                self.assertEqual(0, result.returncode, result.stderr)
                operation = json.loads(result.stdout)["operations"][0]
                self.assertEqual(status, operation["receipt_status"])
                self.assertIn(gap, operation["gaps"])

    def test_emitter_rejects_invalid_f4_event_without_writing(self):
        output = self.root / "output/emitted.jsonl"
        environment = os.environ.copy()
        environment["SAVIA_TELEMETRY_FILE"] = str(output)
        result = subprocess.run(
            [
                "bash", str(ROOT / "scripts/otel-emit.sh"), "operation.started",
                "operation_id=bad", "request_id=request", "flow_id=flow:read",
                f"model_revision={self.model['model_revision']}",
                "frontend_id=fixture", "sequence=0", "outcome=unknown",
            ],
            cwd=ROOT, env=environment, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

        self.assertEqual(2, result.returncode)
        self.assertIn("INVALID_OPERATION_EVENT", result.stderr)
        self.assertFalse(output.exists())

    def test_emitter_preserves_nullable_f4_fields(self):
        output = self.root / "output/emitted.jsonl"
        environment = os.environ.copy()
        environment["SAVIA_TELEMETRY_FILE"] = str(output)
        result = subprocess.run(
            [
                "bash", str(ROOT / "scripts/otel-emit.sh"), "operation.started",
                "operation_id=" + "8" * 32, "request_id=null",
                "flow_id=flow:read",
                f"model_revision={self.model['model_revision']}",
                "frontend_id=fixture", "sequence=0", "outcome=unknown",
            ],
            cwd=ROOT, env=environment, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        event = json.loads(output.read_text())
        self.assertIsNone(event["request_id"])

    def test_emitter_does_not_retype_legacy_null_strings(self):
        output = self.root / "output/legacy.jsonl"
        environment = os.environ.copy()
        environment["SAVIA_TELEMETRY_FILE"] = str(output)
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/otel-emit.sh"), "agent.started",
             "note=null"],
            cwd=ROOT, env=environment, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual("null", json.loads(output.read_text())["note"])

    def test_redacted_operation_is_counted_without_identity(self):
        output = self.root / "output/redacted.jsonl"
        environment = os.environ.copy()
        environment.update({
            "SAVIA_TELEMETRY_FILE": str(output),
            "SAVIA_TELEMETRY_REDACT": "1",
        })
        result = subprocess.run(
            ["bash", str(ROOT / "scripts/otel-emit.sh"), "operation.started",
             "operation_id=" + "9" * 32, "request_id=private-request"],
            cwd=ROOT, env=environment, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(
            {"schema", "ts", "event"},
            set(json.loads(output.read_text())),
        )

        trace = self._cli("trace", "--events", str(output))
        self.assertEqual(0, trace.returncode, trace.stderr)
        report = json.loads(trace.stdout)
        self.assertEqual(1, report["summary"]["redacted_unlinkable"])
        self.assertEqual([], report["operations"])

    def test_telemetry_schema_closes_f4_events_only(self):
        schema = json.loads((ROOT / "config/telemetry-schema.json").read_text())
        validator = Draft7Validator(schema)
        valid = self._complete_events(0, 5)[0]

        self.assertEqual([], list(validator.iter_errors(valid)))
        invalid = dict(valid, unexpected="not-allowed")
        self.assertTrue(list(validator.iter_errors(invalid)))
        misplaced = dict(valid, phase="INTENT")
        self.assertTrue(list(validator.iter_errors(misplaced)))
        legacy = {
            "schema": "savia.event/1.0", "ts": "2026-09-16T08:00:00Z",
            "event": "agent.started", "legacy_extension": "allowed",
        }
        self.assertEqual([], list(validator.iter_errors(legacy)))


if __name__ == "__main__":
    unittest.main()
