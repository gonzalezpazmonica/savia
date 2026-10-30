"""SE-489 R1 — tests del corpus sintético (stdlib, sin dependencias)."""
import os
import re
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
BENCH = os.path.dirname(HERE)
sys.path.insert(0, BENCH)

import corpus_synth as cs  # noqa: E402


def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    return dict(l.split(": ", 1) for l in m.group(1).splitlines()) if m else {}


class CorpusSynthTest(unittest.TestCase):
    def setUp(self):
        self.corpus = cs.build_corpus()

    def test_deterministic(self):
        self.assertEqual(self.corpus, cs.build_corpus())

    def test_committed_corpus_matches_generator(self):
        # El corpus versionado es exactamente la salida del generador: ni ficheros de más ni de menos.
        for dome, files in self.corpus.items():
            root = os.path.join(BENCH, "corpus", dome)
            on_disk = set()
            for d, _, names in os.walk(root):
                on_disk |= {os.path.relpath(os.path.join(d, n), root) for n in names}
            self.assertEqual(on_disk, set(files), dome)
            for rel, txt in files.items():
                with open(os.path.join(root, rel), encoding="utf-8") as fh:
                    self.assertEqual(fh.read(), txt, rel)

    def test_near_identical_contract_codes(self):
        codes = cs.CONTRACT_CODES
        self.assertEqual(len(codes), len(set(codes)))
        # Cada código tiene otro a un dígito de distancia o con el número permutado.
        def near(a, b):
            da, db = a.replace("-", ""), b.replace("-", "")
            one_digit = sum(x != y for x, y in zip(da, db)) == 1
            perm = a[:8] == b[:8] and sorted(a[8:]) == sorted(b[8:])
            return a != b and (one_digit or perm)
        for c in codes:
            self.assertTrue(any(near(c, o) for o in codes), c)
        self.assertFalse(near("CT-2026-104", "CT-2026-999"))

    def test_annex_iv_only_where_declared(self):
        legal = self.corpus["bench-legal"]
        for i, code in enumerate(cs.CONTRACT_CODES):
            has = f"contratos/{code}/anexo-IV.md" in legal
            self.assertEqual(has, cs.contract_params(i)["has_annex_iv"], code)
            self.assertNotIn(f"contratos/{code}/anexo-V.md", legal)
            self.assertIn("Anexo V", legal[f"contratos/{code}/contrato.md"])

    def test_norm_revision_chain(self):
        legal = self.corpus["bench-legal"]
        for code in cs.NORM_CODES:
            revs = sorted(k for k in legal if k.startswith(f"normas/{code}/"))
            self.assertGreaterEqual(len(revs), 3, code)
            prev_to = None
            for n, rel in enumerate(revs, 1):
                fm = frontmatter(legal[rel])
                self.assertEqual(fm["revision"], str(n))
                if prev_to is not None:
                    self.assertEqual(fm["effective_from"], prev_to, rel)
                    self.assertEqual(fm["supersedes"], f"normas/{code}/rev-{n - 1}.md")
                last = n == len(revs)
                self.assertEqual("superseded_by" in fm, not last, rel)
                self.assertEqual(fm["status"] == "active", last, rel)
                prev_to = fm.get("effective_to")
                if prev_to:
                    self.assertLess(fm["effective_from"], prev_to)

    def test_quarantine_notes_have_uninterpretable_level(self):
        for rel, txt in self.corpus["bench-legal"].items():
            if rel.startswith("notas/"):
                level = frontmatter(txt)["confidentiality"]
                self.assertNotIn(level, {"N1", "N2", "N3", "N4", "N4B"}, rel)

    def test_restricted_dome_is_n3(self):
        for rel, txt in self.corpus["bench-restringida"].items():
            self.assertEqual(frontmatter(txt)["confidentiality"], "N3", rel)

    def test_every_doc_declares_synthetic(self):
        for dome, files in self.corpus.items():
            for rel, txt in files.items():
                if not rel.startswith("notas/"):
                    self.assertRegex(txt, r"(?i)ficti|sintétic", rel)


if __name__ == "__main__":
    unittest.main()
