"""SE-397 F1 contract tests for the minimal read-only SAM."""
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
        self.assertEqual({"foundation", "capabilities", "structural"}, set(views))
        for name, view in views.items():
            self.assertEqual(name, view["view"])
            self.assertEqual(model["model_revision"], view["model_revision"])
            self.assertTrue(set(view["node_ids"]) <= node_ids)
            self.assertTrue(set(view["edge_ids"]) <= edge_ids)
            self.assertEqual(["GENERATED_FROM_SAM", "REPORT_ONLY"], view["limitations"])

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
