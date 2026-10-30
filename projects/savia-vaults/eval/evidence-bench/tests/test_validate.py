"""SE-489 R1 — tests del validador del banco (esquema + evidencia contra ficheros)."""
import copy
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.dirname(HERE)
sys.path.insert(0, BENCH)

import validate as v  # noqa: E402

DOC = "# Regla X\n\nIntro.\n\n## Git\n\nNUNCA   push --force en ramas ajenas.\n\n## Otra\n\nTexto distinto.\n"
SYN = "---\ntitle: t\n---\n# Contrato\n\n## Cláusula 5. Penalizaciones\n\nCada hora de retraso genera una penalización del 1 %.\n"


def git(cwd, *args):
    return subprocess.run(["git", "-C", cwd, *args], check=True, capture_output=True, text=True).stdout.strip()


class Fixture:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        git(self.root, "init", "-q")
        git(self.root, "config", "user.email", "bench@example.invalid")
        git(self.root, "config", "user.name", "bench")
        os.makedirs(os.path.join(self.root, "docs"))
        with open(os.path.join(self.root, "docs/regla.md"), "w", encoding="utf-8") as fh:
            fh.write(DOC)
        git(self.root, "add", ".")
        git(self.root, "commit", "-q", "-m", "snap")
        self.snapshot = git(self.root, "rev-parse", "HEAD")
        os.makedirs(os.path.join(self.root, "corpus/legal"))
        with open(os.path.join(self.root, "corpus/legal/c.md"), "w", encoding="utf-8") as fh:
            fh.write(SYN)
        self.manifest = {
            "bench": "test", "version": 1, "snapshot_commit": self.snapshot,
            "min_per_category": 1, "test_ratio": 0.5,
            "domes": {
                "savia-docs": {"source": "git", "root": "", "confidentiality": "N1"},
                "legal": {"source": "worktree", "root": "corpus/legal", "confidentiality": "N2"},
                "secreta": {"source": "worktree", "root": "corpus/legal", "confidentiality": "N3"},
            },
        }
        self.real_rev = git(self.root, "rev-parse", f"{self.snapshot}:docs/regla.md")
        self.syn_rev = v.blob_sha(SYN.encode())

    def case(self, cid, cat, split):
        return {
            "id": cid, "category": cat, "query": "¿se puede hacer push --force?", "intent": "negation",
            "scope": {"allowed_domes": ["savia-docs", "legal"], "as_of": "2026-01-01" if cat == "D" else None},
            "expected": {
                "answer_facts": ["no"],
                "required_evidence": [{"dome": "savia-docs", "document": "docs/regla.md", "revision": self.real_rev,
                                       "locator": {"section": "Git", "quote": "NUNCA push --force"}}],
                "forbidden_evidence": [{"dome": "legal", "document": "c.md", "reason": "otro documento"}],
                "must_abstain": False, "max_unauthorized_reads": 0,
            },
            "split": split,
        }

    def cases(self):
        out = []
        for cat in "ABCDEF":
            out.append(self.case(f"{cat}-001", cat, "dev"))
            out.append(self.case(f"{cat}-002", cat, "test"))
        return out

    def run(self, cases, hidden=False):
        return v.validate(cases, self.manifest, self.root, hidden=hidden)


class ValidateTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fx = Fixture()
        with open(os.path.join(BENCH, "schema.json"), encoding="utf-8") as fh:
            cls.schema = json.load(fh)

    def errors(self, mutate=None, hidden=False):
        cases = self.fx.cases()
        if mutate:
            mutate(cases)
        return self.fx.run(cases, hidden=hidden)

    def test_valid_bench_passes(self):
        self.assertEqual(self.errors(), [])

    def test_synthetic_evidence_with_worktree_revision(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"] = [{"dome": "legal", "document": "c.md", "revision": self.fx.syn_rev,
                                                       "locator": {"section": "Cláusula 5. Penalizaciones", "quote": "penalización del 1 %"}}]
            cs[0]["expected"]["forbidden_evidence"] = []
        self.assertEqual(self.errors(m), [])

    def test_quote_absent_fails(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"][0]["locator"]["quote"] = "NUNCA borrar ramas"
        self.assertTrue(any("quote" in e for e in self.errors(m)))

    def test_quote_in_wrong_section_fails(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"][0]["locator"]["section"] = "Otra"
        self.assertTrue(any("quote" in e for e in self.errors(m)))

    def test_missing_section_fails(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"][0]["locator"]["section"] = "No existe"
        self.assertTrue(any("section" in e for e in self.errors(m)))

    def test_wrong_revision_fails(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"][0]["revision"] = "0" * 40
        self.assertTrue(any("revision" in e for e in self.errors(m)))

    def test_missing_document_fails(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"][0]["document"] = "docs/no-existe.md"
        self.assertTrue(any("no existe" in e for e in self.errors(m)))

    def test_forbidden_document_must_exist(self):
        def m(cs):
            cs[0]["expected"]["forbidden_evidence"][0]["document"] = "fantasma.md"
        self.assertTrue(any("forbidden" in e for e in self.errors(m)))

    def test_required_outside_scope_fails(self):
        def m(cs):
            cs[0]["scope"]["allowed_domes"] = ["legal"]
        self.assertTrue(any("allowed_domes" in e for e in self.errors(m)))

    def test_unknown_dome_fails(self):
        def m(cs):
            cs[0]["scope"]["allowed_domes"].append("otra")
        self.assertTrue(any("cúpula" in e for e in self.errors(m)))

    def test_category_d_requires_as_of(self):
        def m(cs):
            cs[6]["scope"]["as_of"] = None
        self.assertTrue(any("as_of" in e for e in self.errors(m)))

    def test_answer_requires_evidence(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"] = []
        self.assertTrue(any("required_evidence" in e for e in self.errors(m)))

    def test_abstention_without_evidence_is_valid(self):
        def m(cs):
            cs[0]["expected"]["required_evidence"] = []
            cs[0]["expected"]["must_abstain"] = True
            cs[0]["expected"]["answer_facts"] = []
        self.assertEqual(self.errors(m), [])

    def test_unauthorized_reads_must_be_zero(self):
        def m(cs):
            cs[0]["expected"]["max_unauthorized_reads"] = 1
        self.assertTrue(any("max_unauthorized_reads" in e for e in self.errors(m)))

    def test_schema_rejects_unknown_field(self):
        def m(cs):
            cs[0]["extra"] = 1
        self.assertTrue(any("extra" in e for e in self.errors(m)))

    def test_schema_rejects_bad_category(self):
        def m(cs):
            cs[0]["category"] = "G"
        self.assertTrue(any("category" in e for e in self.errors(m)))

    def test_duplicate_id_fails(self):
        def m(cs):
            cs[1]["id"] = cs[0]["id"]
        self.assertTrue(any("duplicado" in e for e in self.errors(m)))

    def test_same_evidence_required_and_forbidden_fails(self):
        def m(cs):
            ev = cs[0]["expected"]["required_evidence"][0]
            cs[0]["expected"]["forbidden_evidence"] = [{"dome": ev["dome"], "document": ev["document"], "reason": "mismo documento"}]
        self.assertTrue(any("requerida y prohibida" in e for e in self.errors(m)))

    def test_minimum_per_category(self):
        self.fx.manifest["min_per_category"] = 3
        try:
            self.assertTrue(any("mínimo" in e for e in self.errors()))
            self.assertEqual(self.errors(hidden=True), [])
        finally:
            self.fx.manifest["min_per_category"] = 1

    def test_split_ratio_enforced(self):
        def m(cs):
            cs[1]["split"] = "dev"
        self.assertTrue(any("split" in e for e in self.errors(m)))
        self.assertEqual(self.errors(m, hidden=True), [])

    def test_missing_snapshot_is_fail_closed(self):
        man = copy.deepcopy(self.fx.manifest)
        man["snapshot_commit"] = "f" * 40
        errs = v.validate(self.fx.cases(), man, self.fx.root)
        # Toda evidencia del corpus real falla con el diagnóstico explícito, no con un «no existe» genérico.
        real = [e for e in errs if "savia-docs" in e]
        self.assertTrue(real)
        self.assertTrue(all("snapshot_commit" in e for e in real), real[:2])

    def test_no_git_repo_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as d:
            errs = v.validate(self.fx.cases(), self.fx.manifest, d)
        self.assertTrue(any("snapshot_commit" in e for e in errs))

    def test_mini_schema_engine(self):
        s = {"type": "object", "required": ["a"], "additionalProperties": False,
             "properties": {"a": {"type": "string", "pattern": "^x", "minLength": 2},
                            "b": {"type": "array", "minItems": 1, "items": {"enum": [1, 2]}},
                            "c": {"type": ["string", "null"]}, "d": {"const": 0}}}
        self.assertEqual(v.check_schema({"a": "xy", "b": [1], "c": None, "d": 0}, s), [])
        self.assertTrue(v.check_schema({"a": "yy"}, s))
        self.assertTrue(v.check_schema({"a": "x"}, s))
        self.assertTrue(v.check_schema({"a": "xy", "b": []}, s))
        self.assertTrue(v.check_schema({"a": "xy", "b": [3]}, s))
        self.assertTrue(v.check_schema({"a": "xy", "c": 1}, s))
        self.assertTrue(v.check_schema({"a": "xy", "d": 1}, s))
        self.assertTrue(v.check_schema({}, s))
        self.assertTrue(v.check_schema({"a": True}, s))

    def test_cli_exit_codes(self):
        with tempfile.TemporaryDirectory() as d:
            good, bad = os.path.join(d, "g.jsonl"), os.path.join(d, "b.jsonl")
            man = os.path.join(d, "m.json")
            with open(man, "w") as fh:
                json.dump(self.fx.manifest, fh)
            cases = self.fx.cases()
            with open(good, "w") as fh:
                fh.write("".join(json.dumps(c) + "\n" for c in cases))
            cases[0]["expected"]["required_evidence"][0]["revision"] = "1" * 40
            with open(bad, "w") as fh:
                fh.write("".join(json.dumps(c) + "\n" for c in cases))
            run = lambda f: subprocess.run([sys.executable, os.path.join(BENCH, "validate.py"), "--cases", f,
                                            "--manifest", man, "--repo", self.fx.root], capture_output=True, text=True)
            self.assertEqual(run(good).returncode, 0)
            self.assertEqual(run(bad).returncode, 1)
            self.assertEqual(run(os.path.join(d, "no.jsonl")).returncode, 2)


if __name__ == "__main__":
    unittest.main()
