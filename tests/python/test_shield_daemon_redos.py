"""CodeQL #58 (py/polynomial-redos) in scripts/savia-shield-daemon.py.

The keyword-argument filter used r'\\w+\\s*=\\s*["\\']' with re.search: on a long
run of word characters without "=" every start position re-scans the run,
O(n^2) — 20 000 "0" took ~4.6 s per NER entity. One \\w gives the same
matches in linear time.
"""
import importlib.util
import time
import types
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "savia_shield_daemon_under_test", ROOT / "scripts" / "savia-shield-daemon.py"
)
daemon = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(daemon)


class _WholeTextNer:
    """Fake Presidio analyzer that marks the whole text as one PERSON."""

    def analyze(self, text, language, score_threshold):
        return [types.SimpleNamespace(start=0, end=len(text),
                                      entity_type="PERSON", score=0.99)]


class ShieldRedosTests(unittest.TestCase):
    def setUp(self):
        self._ner = daemon.ner
        daemon.ner = _WholeTextNer()

    def tearDown(self):
        daemon.ner = self._ner

    def test_long_word_run_is_scanned_in_linear_time(self):
        start = time.monotonic()
        daemon.scan("0" * 20000, th=0.7)
        self.assertLess(time.monotonic() - start, 1.0)

    def test_keyword_argument_fragment_is_still_filtered(self):
        result = daemon.scan('encoding = "utf-8 Maria', th=0.7)
        self.assertEqual(result["entities"], [])

    def test_plain_entity_still_reported(self):
        result = daemon.scan("Maria Lopez Garcia", th=0.7)
        self.assertEqual(result["verdict"], "PII_DETECTED")


if __name__ == "__main__":
    unittest.main()
