"""SE-489 M2 — tests del generador de tablas de la medición (regla AC-6 y render)."""
import io
import contextlib
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import m2_report as r  # noqa: E402


def d(diff, lo, hi):
    return {"n": 50, "diff": diff, "lo": lo, "hi": hi}


class Verdict(unittest.TestCase):
    def test_ab_no_inferioridad_usa_el_limite_inferior(self):
        self.assertEqual(r.verdict("A", d(0.0, -0.009, 0.02)), "no inferior")
        # Límite exacto de -1 pp: no es no-inferior (estricto).
        self.assertEqual(r.verdict("B", d(0.0, -0.01, 0.02)), "inferior o no concluyente")
        self.assertEqual(r.verdict("A", d(-0.05, -0.1, 0.0)), "inferior o no concluyente")

    def test_cde_gana_solo_si_el_ic_excluye_cero_por_arriba(self):
        self.assertEqual(r.verdict("C", d(0.1, 0.01, 0.2)), "gana")
        self.assertEqual(r.verdict("D", d(0.1, 0.0, 0.2)), "no concluyente")
        self.assertEqual(r.verdict("E", d(-0.1, -0.2, -0.01)), "pierde")

    def test_f_y_sin_datos(self):
        self.assertEqual(r.verdict("F", d(0.5, 0.4, 0.6)), "-")
        self.assertEqual(r.verdict("A", None), "sin datos")


class Render(unittest.TestCase):
    def test_diff_formato_y_vacio(self):
        self.assertEqual(r.diff(d(0.0123, -0.01, 0.03)), "+0.012 [-0.010, +0.030]")
        self.assertEqual(r.diff(None), "-")

    def test_main_imprime_tabla_con_veredicto(self):
        import json
        import tempfile

        iv = lambda m: {"n": 5, "mean": m, "lo": m, "hi": m}  # noqa: E731
        metrics = lambda m: {k: iv(m) for k in r.HEAD}  # noqa: E731
        case = {"metrics": {"unauthorizedReads": 0}}
        rep = lambda m: {  # noqa: E731
            "errors": 0, "violations": 0, "byCategory": {"A": metrics(m)}, "cases": [case],
            "latency": {"p50Ms": 1, "p95Ms": 2}, "cost": {"modelCalls": 3}, "rssPeakMb": 100,
        }
        cmp_ = {"byCategory": {"A": {k: d(0.1, 0.05, 0.15) for k in r.HEAD}}, "overall": {k: d(0.1, 0.05, 0.15) for k in r.HEAD}}
        data = {"models": {"x": "y"}, "sets": {"dev": {"n": 5, "M0": rep(0.5), "configs": {
            "x-N20": {"report": rep(0.6), "vsM0": cmp_, "rerankerLatency": {"p50Ms": 10, "p95Ms": 20, "meanMsPerPair": 1.5, "failed": 0}}}}}}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            json.dump(data, fh)
        buf = io.StringIO()
        try:
            with contextlib.redirect_stdout(buf):
                r.main([fh.name])
        finally:
            os.unlink(fh.name)
        out = buf.getvalue()
        self.assertIn("x-N20", out)
        self.assertIn("no inferior", out)
        self.assertIn("0.500→0.600", out)


if __name__ == "__main__":
    unittest.main()
