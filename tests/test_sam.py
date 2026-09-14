"""SE-397 F1/F2 contract tests for the read-only SAM."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/sam/valid"
sys.path.insert(0, str(ROOT / "scripts"))

from sam_model import (  # noqa: E402
    SamValidationError,
    build_model,
    build_views,
    canonical_json,
    query_node,
    validate_model,
)


class SamTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name) / "repo"
        shutil.copytree(FIXTURE, self.root)
        self._git("init", "-q")
        self._git("config", "user.name", "SAM Tests")
        self._git("config", "user.email", "sam-tests@localhost")
        self._git("add", ".")
        self._git("commit", "-qm", "fixture")

    def tearDown(self):
        self.temp.cleanup()

    def _git(self, *args: str) -> None:
        subprocess.run(["git", *args], cwd=self.root, check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    def _cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(ROOT / "scripts/sam.py"), *args, "--root", str(self.root)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        )

    def _declarations(self) -> dict:
        return json.loads((self.root / ".scm/sam-declarations.json").read_text())

    def _write_declarations(self, value: dict) -> None:
        (self.root / ".scm/sam-declarations.json").write_text(
            json.dumps(value, indent=2) + "\n", encoding="utf-8"
        )

    def _runtime_declarations(self) -> dict:
        return json.loads(
            (self.root / ".scm/sam-runtime-declarations.json").read_text()
        )

    def _write_runtime_declarations(self, value: dict) -> None:
        (self.root / ".scm/sam-runtime-declarations.json").write_text(
            json.dumps(value, indent=2) + "\n", encoding="utf-8"
        )

    @staticmethod
    def _refresh_edge_sources(document: dict, edge: dict) -> None:
        nodes = {node["id"]: node for node in document["nodes"]}
        edge["source_paths"] = sorted(set(
            nodes[edge["source"]]["source_paths"]
            + nodes[edge["target"]]["source_paths"]
        ))

    def _generate(self) -> dict:
        result = self._cli("generate")
        self.assertEqual(0, result.returncode, result.stderr)
        return json.loads((self.root / ".scm/sam.json").read_text())

    def test_deterministic_generation_across_identical_git_repositories(self):
        first = self._generate()
        first_bytes = {
            p.relative_to(self.root): p.read_bytes()
            for p in [self.root / ".scm/sam.json", *sorted((self.root / ".scm/views").glob("*.json"))]
        }
        second_result = self._cli("generate")
        self.assertEqual(0, second_result.returncode, second_result.stderr)
        second_bytes = {p: (self.root / p).read_bytes() for p in first_bytes}
        self.assertEqual(first_bytes, second_bytes)
        payload = {k: first[k] for k in ("inputs", "nodes", "edges", "known_unknowns")}
        self.assertEqual(hashlib.sha256(canonical_json(payload)).hexdigest(), first["model_revision"])

    def test_registry_capability_is_reused_with_component_and_edge(self):
        model = build_model(self.root)
        ids = {node["id"] for node in model["nodes"]}
        self.assertIn("capability/script:scripts/tool", ids)
        self.assertIn("component/scripts/tool.sh", ids)
        self.assertIn(
            ("component/scripts/tool.sh", "IMPLEMENTS", "capability/script:scripts/tool"),
            {(e["source"], e["relation"], e["target"]) for e in model["edges"]},
        )
        provenance = next(n for n in model["nodes"] if n["id"] == "capability/script:scripts/tool")["provenance"]
        self.assertEqual({"DISCOVERED"}, {p["source_kind"] for p in provenance})
        self.assertEqual({".scm/registry.json", "scripts/tool.sh"}, {p["source_path"] for p in provenance})

    def test_source_paths_fail_closed_without_partial_writes(self):
        outside = Path(self.temp.name) / "outside.txt"
        outside.write_text("outside")
        cases = ["missing.txt", "/etc/passwd", "../outside.txt", "escape"]
        for value in cases:
            with self.subTest(value=value):
                declarations = self._declarations()
                declarations["nodes"][0]["source_paths"] = [value]
                self._write_declarations(declarations)
                if value == "escape":
                    (self.root / "escape").symlink_to(outside)
                result = self._cli("generate")
                self.assertEqual(2, result.returncode)
                self.assertFalse((self.root / ".scm/sam.json").exists())
                shutil.copy(FIXTURE / ".scm/sam-declarations.json",
                            self.root / ".scm/sam-declarations.json")
                (self.root / "escape").unlink(missing_ok=True)

    def test_closed_schema_rejects_structural_errors(self):
        mutations = {
            "UNKNOWN_FIELD": lambda d: d.update(extra=True),
            "DUPLICATE_ID": lambda d: d["nodes"].append(copy.deepcopy(d["nodes"][0])),
            "DUPLICATE_EDGE": lambda d: d["edges"].append(copy.deepcopy(d["edges"][0])),
            "DANGLING_EDGE": lambda d: d["edges"][0].update(target="component:missing"),
            "UNKNOWN_NODE_TYPE": lambda d: d["nodes"][0].update(type="RUNTIME"),
            "UNKNOWN_RELATION": lambda d: d["edges"][0].update(relation="CALLS"),
        }
        for code, mutate in mutations.items():
            with self.subTest(code=code):
                declarations = self._declarations()
                mutate(declarations)
                self._write_declarations(declarations)
                with self.assertRaises(SamValidationError) as raised:
                    build_model(self.root)
                self.assertEqual(code, raised.exception.code)
                shutil.copy(FIXTURE / ".scm/sam-declarations.json",
                            self.root / ".scm/sam-declarations.json")

    def test_changed_source_makes_check_stale_and_revision_changes(self):
        first = self._generate()["model_revision"]
        self.assertEqual(0, self._cli("check").returncode)
        tool = self.root / "scripts/tool.sh"
        original = tool.read_bytes()
        tool.write_bytes(original + b"# changed\n")
        self.assertEqual(1, self._cli("check").returncode)
        second = self._generate()["model_revision"]
        self.assertNotEqual(first, second)
        tool.write_bytes(original)
        self.assertEqual(first, self._generate()["model_revision"])

    def test_query_rejects_corruption_and_returns_explicit_unknown(self):
        self._generate()
        unknown = self._cli("query", "--node", "component:not-present")
        self.assertEqual(0, unknown.returncode, unknown.stderr)
        self.assertEqual(
            {"status": "UNKNOWN", "node": None, "edges": []},
            json.loads(unknown.stdout),
        )
        model_path = self.root / ".scm/sam.json"
        model = json.loads(model_path.read_text())
        model["nodes"][0]["extra"] = True
        model_path.write_text(json.dumps(model))
        corrupt = self._cli("query", "--node", "system:savia")
        self.assertEqual(2, corrupt.returncode)
        self.assertIn("INVALID_MODEL", corrupt.stderr)

    def test_generated_model_cannot_self_upgrade_provenance(self):
        model = build_model(self.root)
        upgraded = copy.deepcopy(model)
        upgraded["nodes"][0]["provenance"][0]["source_kind"] = "VERIFIED_STATIC"
        with self.assertRaises(SamValidationError) as raised:
            validate_model(upgraded, self.root)
        self.assertEqual("UNSUPPORTED_SOURCE_KIND", raised.exception.code)

    def test_malformed_generated_field_types_fail_closed(self):
        model = build_model(self.root)
        mutations = [
            lambda value: value["known_unknowns"].append({"not": "a string"}),
            lambda value: value["edges"][0].update(relation=[]),
            lambda value: value["nodes"][0]["provenance"][0].update(source_path=[]),
        ]
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                malformed = copy.deepcopy(model)
                mutate(malformed)
                with self.assertRaises(SamValidationError):
                    validate_model(malformed, self.root)

    def test_generation_preserves_existing_scm_bytes(self):
        existing = {
            path.relative_to(self.root): path.read_bytes()
            for path in (self.root / ".scm").rglob("*") if path.is_file()
        }
        self._generate()
        for relative, content in existing.items():
            self.assertEqual(content, (self.root / relative).read_bytes(), relative)

    def test_views_reference_only_model_records(self):
        model = self._generate()
        node_ids = {n["id"] for n in model["nodes"]}
        edge_ids = {f'{e["source"]}|{e["relation"]}|{e["target"]}' for e in model["edges"]}
        views = build_views(model)
        self.assertEqual(
            {"foundation", "capabilities", "structural", "runtime", "authority", "failure"},
            set(views),
        )
        for name, view in views.items():
            self.assertEqual(name, view["view"])
            self.assertEqual(model["model_revision"], view["model_revision"])
            self.assertTrue(set(view["node_ids"]) <= node_ids)
            self.assertTrue(set(view["edge_ids"]) <= edge_ids)
            expected = ["GENERATED_FROM_SAM", "REPORT_ONLY"]
            if name in {"runtime", "authority", "failure"}:
                expected = ["DECLARED_NOT_OBSERVED", *expected]
            self.assertEqual(expected, view["limitations"])

    def test_f2_runtime_model_has_closed_v2_topology(self):
        model = build_model(self.root)
        self.assertEqual(2, model["schema_version"])
        nodes = {node["id"]: node for node in model["nodes"]}
        flows = sorted(node_id for node_id, node in nodes.items() if node["type"] == "FLOW")
        self.assertEqual([
            "flow:bash", "flow:edit", "flow:external-effect",
            "flow:mcp", "flow:read", "flow:write",
        ], flows)
        runtime_relations = {
            "HAS_EFFECT", "HAS_RISK", "HAS_EXECUTION_AUTHORITY",
            "REQUIRES_HUMAN", "GATES", "DEGRADES_TO",
        }
        runtime_edges = [edge for edge in model["edges"] if edge["relation"] in runtime_relations]
        self.assertEqual(31, len(runtime_edges))
        for flow in flows:
            outgoing = [edge for edge in runtime_edges if edge["source"] == flow]
            incoming = [edge for edge in runtime_edges if edge["target"] == flow]
            self.assertEqual(1, sum(edge["relation"] == "HAS_EFFECT" for edge in outgoing))
            self.assertEqual(1, sum(edge["relation"] == "HAS_RISK" for edge in outgoing))
            self.assertEqual(1, sum(edge["relation"] == "HAS_EXECUTION_AUTHORITY" for edge in outgoing))
            self.assertEqual(1, sum(edge["relation"] == "DEGRADES_TO" for edge in outgoing))
            self.assertEqual(1, sum(edge["relation"] == "GATES" for edge in incoming))
        external = [
            (edge["relation"], edge["target"])
            for edge in runtime_edges if edge["source"] == "flow:external-effect"
        ]
        self.assertIn(("REQUIRES_HUMAN", "authority:human-decision"), external)
        self.assertEqual({"DECLARED"}, {
            item["source_kind"]
            for edge in runtime_edges for item in edge["provenance"]
        })
        self.assertEqual([
            "AUTHORITY_PATHS_DECLARED_NOT_ENFORCED",
            "CAPABILITY_DEPENDENCIES_INCOMPLETE",
            "CAPABILITY_TEST_LINKS_INCOMPLETE",
            "FAILURE_PATHS_INCOMPLETE",
            "OPERATIONAL_EVIDENCE_NOT_MODELLED",
            "RUNTIME_ARCHITECTURE_DECLARED_NOT_OBSERVED",
        ], model["known_unknowns"])

    def test_runtime_matrix_mutations_fail_closed(self):
        cases = []

        missing_human = self._runtime_declarations()
        missing_human["edges"] = [edge for edge in missing_human["edges"] if not (
            edge["source"] == "flow:external-effect"
            and edge["relation"] == "REQUIRES_HUMAN"
        )]
        cases.append(missing_human)

        permissive_bash = self._runtime_declarations()
        edge = next(edge for edge in permissive_bash["edges"] if
                    edge["source"] == "flow:bash" and edge["relation"] == "HAS_RISK")
        edge["target"] = "risk:L0"
        self._refresh_edge_sources(permissive_bash, edge)
        cases.append(permissive_bash)

        wrong_gate = self._runtime_declarations()
        edge = next(edge for edge in wrong_gate["edges"] if
                    edge["target"] == "flow:write" and edge["relation"] == "GATES")
        edge["source"] = "human-gate:not-required-within-approved-scope"
        self._refresh_edge_sources(wrong_gate, edge)
        cases.append(wrong_gate)

        for declaration in cases:
            with self.subTest(case=cases.index(declaration)):
                self._write_runtime_declarations(declaration)
                with self.assertRaises(SamValidationError) as raised:
                    build_model(self.root)
                self.assertEqual("INCOMPLETE_FLOW", raised.exception.code)
                shutil.copy(
                    FIXTURE / ".scm/sam-runtime-declarations.json",
                    self.root / ".scm/sam-runtime-declarations.json",
                )

    def test_runtime_declaration_paths_and_cross_manifest_ids_fail_closed(self):
        runtime = self._runtime_declarations()
        runtime["nodes"][0]["source_paths"] = ["../outside.txt"]
        self._write_runtime_declarations(runtime)
        result = self._cli("generate")
        self.assertEqual(2, result.returncode)
        self.assertIn("PATH_OUTSIDE_ROOT", result.stderr)
        self.assertFalse((self.root / ".scm/sam.json").exists())

        runtime = json.loads(
            (FIXTURE / ".scm/sam-runtime-declarations.json").read_text()
        )
        runtime["nodes"][0]["id"] = "system:savia"
        self._write_runtime_declarations(runtime)
        with self.assertRaises(SamValidationError) as raised:
            build_model(self.root)
        self.assertEqual("DUPLICATE_ID", raised.exception.code)

    def test_runtime_unknown_vocabulary_is_rejected(self):
        runtime = self._runtime_declarations()
        runtime["edges"][0]["relation"] = "ALLOWS"
        self._write_runtime_declarations(runtime)
        with self.assertRaises(SamValidationError) as raised:
            build_model(self.root)
        self.assertEqual("UNKNOWN_RELATION", raised.exception.code)

    def test_schema_v1_generated_model_is_rejected_after_f2(self):
        self._generate()
        model_path = self.root / ".scm/sam.json"
        model = json.loads(model_path.read_text())
        model["schema_version"] = 1
        model_path.write_text(json.dumps(model), encoding="utf-8")
        result = self._cli("query", "--node", "flow:read")
        self.assertEqual(2, result.returncode)
        self.assertIn("INVALID_MODEL", result.stderr)

    def test_stale_or_malformed_registry_fails_without_rewrite(self):
        registry = self.root / ".scm/registry.json"
        original = registry.read_bytes()
        stub = self.root / "scripts/generate-capability-map.py"
        stub.write_text("raise SystemExit(1)\n")
        self.assertEqual(2, self._cli("generate").returncode)
        self.assertEqual(original, registry.read_bytes())
        stub.write_text((FIXTURE / "scripts/generate-capability-map.py").read_text())
        registry.write_text("{broken")
        result = self._cli("generate")
        self.assertEqual(2, result.returncode)
        self.assertIn("INVALID_REGISTRY", result.stderr)


if __name__ == "__main__":
    unittest.main()
