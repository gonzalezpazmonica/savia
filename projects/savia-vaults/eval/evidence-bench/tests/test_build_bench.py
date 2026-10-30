"""SE-489 R1 — tests del banco generado (cases.jsonl) frente a su generador y su validador."""
import json
import os
import re
import sys
import unittest
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.dirname(HERE)
sys.path.insert(0, BENCH)

import build_bench as bb  # noqa: E402
import validate as v  # noqa: E402


class BuildBenchTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cases = v.load_jsonl(os.path.join(BENCH, "cases.jsonl"))
        with open(os.path.join(BENCH, "manifest.json"), encoding="utf-8") as fh:
            cls.manifest = json.load(fh)
        cls.repo = os.path.abspath(os.path.join(BENCH, "..", "..", "..", ".."))

    def test_committed_cases_match_generator(self):
        built = bb.build_cases(self.repo)
        self.assertEqual([json.dumps(c, sort_keys=True) for c in built],
                         [json.dumps(c, sort_keys=True) for c in self.cases])

    def test_bench_validates_against_files(self):
        # AC-1: ≥ 300 casos que validan; cada required_evidence existe en su revisión.
        errs = v.validate(self.cases, self.manifest, self.repo)
        self.assertEqual(errs, [], "\n".join(errs[:20]))

    def test_counts_and_split(self):
        per = Counter((c["category"], c["split"]) for c in self.cases)
        for cat in "ABCDEF":
            self.assertGreaterEqual(per[(cat, "dev")] + per[(cat, "test")], 50, cat)
            total = per[(cat, "dev")] + per[(cat, "test")]
            self.assertEqual(per[(cat, "test")], round(total * 0.3), cat)
        self.assertGreaterEqual(len(self.cases), 300)

    def test_split_exact_ratio_from_scratch(self):
        keys = [f"consulta {i}" for i in range(50)]
        self.assertEqual(Counter(bb.assign_split(keys).values())["test"], 15)
        self.assertEqual(bb.assign_split(keys), bb.assign_split(list(reversed(keys))))

    def test_split_survives_insertion_and_removal(self):
        # División fija: insertar o quitar casos no mueve a ningún otro entre dev y test.
        keys = [f"consulta {i}" for i in range(50)]
        prev = bb.assign_split(keys)
        new = [f"consulta nueva {i}" for i in range(30)]
        grown = bb.assign_split(keys[:10] + new + keys[10:], previous=prev)
        self.assertTrue(all(grown[k] == prev[k] for k in keys))
        self.assertEqual(Counter(grown.values())["test"], round(80 * 0.3))
        self.assertEqual(Counter(grown[k] for k in new)["test"], round(80 * 0.3) - 15)
        dev = [k for k in keys if prev[k] == "dev"]
        kept = [k for k in keys if k not in dev[:20]]
        shrunk = bb.assign_split(kept, previous=prev)
        # Sin reasignar: test queda por encima del objetivo y lo marca el validador.
        self.assertEqual(shrunk, {k: prev[k] for k in kept})
        self.assertGreater(Counter(shrunk.values())["test"], round(len(kept) * 0.3))

    def test_committed_split_is_preserved_by_query(self):
        prev = {c["query"]: c["split"] for c in self.cases}
        rebuilt = {c["query"]: c["split"] for c in bb.build_cases(self.repo)}
        self.assertEqual(prev, rebuilt)

    def test_generator_imports_only_bench_modules(self):
        # Control de la regla «nada sale del grafo»: el generador solo importa stdlib y módulos del banco.
        import ast
        with open(os.path.join(BENCH, "build_bench.py"), encoding="utf-8") as fh:
            tree = ast.parse(fh.read())
        mods = {a.name.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.Import) for a in n.names}
        mods |= {n.module.split(".")[0] for n in ast.walk(tree) if isinstance(n, ast.ImportFrom) and n.module}
        self.assertLessEqual(mods, {"__future__", "argparse", "datetime", "hashlib", "json", "os", "re",
                                    "subprocess", "sys", "corpus_synth", "validate"})

    def test_category_intents(self):
        intents = {cat: Counter(c["intent"] for c in self.cases if c["category"] == cat) for cat in "ABCDEF"}
        self.assertEqual(set(intents["A"]), {"identifier", "near-identifier", "negation"})
        self.assertEqual(set(intents["B"]), {"paraphrase"})
        self.assertEqual(set(intents["C"]), {"structure-annex"})
        self.assertEqual(set(intents["D"]), {"version-as-of"})
        self.assertEqual(set(intents["E"]), {"multi-document", "aggregation"})
        self.assertEqual(set(intents["F"]), {"unauthorized-dome", "quarantine", "missing-annex",
                                             "contradiction", "injection", "nonexistent-id"})

    def test_structure_cases_split_answer_between_clause_and_annex(self):
        for c in self.cases:
            if c["category"] == "C":
                docs = [e["document"] for e in c["expected"]["required_evidence"]]
                self.assertTrue(any(d.endswith("contrato.md") for d in docs), c["id"])
                self.assertTrue(any("/anexo-" in d for d in docs), c["id"])

    def test_version_cases_forbid_other_revisions(self):
        for c in self.cases:
            if c["category"] != "D" or c["expected"]["must_abstain"]:
                continue
            req = {e["document"] for e in c["expected"]["required_evidence"]}
            forb = {e["document"] for e in c["expected"]["forbidden_evidence"]}
            norm = next(iter(req)).rsplit("/", 1)[0]
            self.assertTrue(forb and all(f.startswith(norm) for f in forb), c["id"])

    def test_restricted_dome_never_authorized(self):
        for c in self.cases:
            self.assertNotIn("bench-restringida", c["scope"]["allowed_domes"], c["id"])
            if c["intent"] in ("unauthorized-dome", "quarantine", "missing-annex", "nonexistent-id"):
                self.assertTrue(c["expected"]["must_abstain"], c["id"])
            if c["intent"] in ("contradiction", "injection"):
                self.assertFalse(c["expected"]["must_abstain"], c["id"])

    def test_queries_unique(self):
        q = Counter(c["query"] for c in self.cases)
        self.assertEqual([k for k, n in q.items() if n > 1], [])

    def test_not_derived_from_link_graph(self):
        # Regla del banco (SE-489 R1): ningún caso sale del grafo de vínculos existente.
        with open(os.path.join(BENCH, "build_bench.py"), encoding="utf-8") as fh:
            src = fh.read()
        self.assertIsNone(re.search(r"vault-links|wikilink|vault_graph|knowledge-graph|links\.json", src))

    def test_no_hidden_cases_in_repo(self):
        self.assertFalse(any(c["id"].startswith("H-") for c in self.cases))


if __name__ == "__main__":
    unittest.main()
