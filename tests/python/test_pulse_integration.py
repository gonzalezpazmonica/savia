#!/usr/bin/env python3
"""Tests de scripts/pulse_integration.py (SE-518 S2: AC-10 y AC-11).

AC-10: tras una fusión solo se integra la siguiente o la que choca; con la huella
igual no se relanzan revisoras; si la huella falla se relanzan (fail-closed).
AC-11: cabeza sin pruebas 15 min → un relanzamiento en el ledger y, si no arranca,
una petición; nunca un segundo relanzamiento automático.
"""
import datetime as dt
import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts", "pulse_integration.py")
_spec = importlib.util.spec_from_file_location("pulse_integration", SCRIPT)
pi = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pi)

T0 = dt.datetime(2026, 11, 14, 10, 0, 0, tzinfo=dt.timezone.utc)
M = dt.timedelta(minutes=1)


def pr(n, m="MERGEABLE", s="CLEAN"):
    return {"number": n, "mergeable": m, "mergeStateStatus": s}


def by_num(decisions):
    return {d["number"]: d for d in decisions}


class PlanIntegration(unittest.TestCase):
    def test_solo_conflicto_y_siguiente(self):
        prs = [pr(1, "CONFLICTING", "DIRTY"), pr(2, "MERGEABLE", "BEHIND"),
               pr(3, "MERGEABLE", "BEHIND"), pr(4)]
        d = by_num(pi.plan_integration(prs, next_pr=2))
        self.assertEqual((d[1]["action"], d[1]["reason"]), ("integrar", "conflicto"))
        self.assertEqual((d[2]["action"], d[2]["reason"]), ("integrar", "siguiente"))
        # NEGATIVO: detrás pero ni choca ni es la siguiente → no se toca (cascada)
        self.assertEqual((d[3]["action"], d[3]["reason"]), ("omitir", "sin_conflicto"))
        self.assertEqual(d[4]["action"], "omitir")

    def test_siguiente_al_dia_no_se_integra(self):
        d = by_num(pi.plan_integration([pr(7)], next_pr=7))
        self.assertEqual((d[7]["action"], d[7]["reason"]), ("omitir", "siguiente_al_dia"))

    def test_desconocido_no_se_toca_ni_siendo_la_siguiente(self):
        d = by_num(pi.plan_integration([pr(5, "UNKNOWN", "UNKNOWN"), {"number": 6}], next_pr=5))
        self.assertEqual(d[5]["action"], "omitir")
        self.assertEqual(d[5]["reason"], "desconocido")
        self.assertEqual(d[6]["reason"], "desconocido")

    def test_politica_desconocida_y_entrada_invalida_fallan_cerrado(self):
        with self.assertRaises(pi.Invalid):
            pi.plan_integration([pr(1)], policy="siempre")
        with self.assertRaises(pi.Invalid):
            pi.plan_integration({"number": 1})
        with self.assertRaises(pi.Invalid):
            pi.plan_integration([{"number": "1"}])
        with self.assertRaises(pi.Invalid):
            pi.plan_integration([pr(1)], next_pr="1")


def git(repo, *a):
    subprocess.run(["git", "-C", repo, "-c", "user.name=t", "-c", "user.email=t@t",
                    "-c", "commit.gpgsign=false"] + list(a), check=True,
                   capture_output=True)


def write(repo, name, text):
    with open(os.path.join(repo, name), "w") as f:
        f.write(text)


class Fingerprint(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.r = self.tmp.name
        git(self.r, "init", "-q", "-b", "main")
        write(self.r, "a.txt", "\n".join("a%d" % i for i in range(30)) + "\n")
        write(self.r, "b.txt", "b\n")
        git(self.r, "add", "."); git(self.r, "commit", "-qm", "base")
        git(self.r, "checkout", "-qb", "pr")
        write(self.r, "feature.txt", "nuevo\n")
        git(self.r, "add", "."); git(self.r, "commit", "-qm", "pr")

    def tearDown(self):
        self.tmp.cleanup()

    def fp(self, head="pr"):
        return pi.content_fingerprint(self.r, "main", head)

    def test_main_avanza_en_otro_sitio_e_integrar_no_cambia_la_huella(self):
        before = self.fp()
        self.assertTrue(before)
        git(self.r, "checkout", "-q", "main")
        write(self.r, "b.txt", "b cambiado en main\n")
        git(self.r, "commit", "-qam", "main avanza")
        git(self.r, "checkout", "-q", "pr")
        git(self.r, "merge", "-q", "--no-edit", "main")
        after = self.fp()
        self.assertEqual(before, after)
        self.assertEqual(pi.reviewers_decision(before, after), ("omitir", "huella_igual"))

    def test_cambio_ajeno_en_el_contexto_de_lo_que_toca_la_propuesta_no_cambia_la_huella(self):
        # La propuesta edita la línea 20 de a.txt; main edita la 17 (dentro del
        # contexto de 3 líneas de la propuesta). Integra limpio y la huella no varía.
        lines = ["a%d" % i for i in range(30)]
        edited = list(lines)
        edited[20] = "a20-propuesta"
        write(self.r, "a.txt", "\n".join(edited) + "\n")
        git(self.r, "commit", "-qam", "pr toca a.txt")
        before = self.fp()
        git(self.r, "checkout", "-q", "main")
        other = list(lines)
        other[17] = "a17-main"
        write(self.r, "a.txt", "\n".join(other) + "\n")
        git(self.r, "commit", "-qam", "main toca el contexto")
        git(self.r, "checkout", "-q", "pr")
        git(self.r, "merge", "-q", "--no-edit", "main")
        self.assertEqual(before, self.fp())

    def test_cambio_del_contenido_de_la_propuesta_cambia_la_huella(self):
        before = self.fp()
        write(self.r, "feature.txt", "nuevo\notra linea\n")
        git(self.r, "commit", "-qam", "mas")
        after = self.fp()
        self.assertNotEqual(before, after)
        self.assertEqual(pi.reviewers_decision(before, after), ("relanzar", "huella_distinta"))

    def test_fallo_del_calculo_devuelve_none_y_relanza(self):
        self.assertIsNone(pi.content_fingerprint(self.r, "main", "no-existe"))
        self.assertIsNone(pi.content_fingerprint(self.r, "rama-ilegible", "pr"))
        self.assertIsNone(pi.content_fingerprint(os.path.join(self.r, "nada"), "main", "pr"))
        self.assertEqual(pi.reviewers_decision("abc", None), ("relanzar", "huella_actual_ilegible"))

    def test_diferencia_vacia_no_es_huella(self):
        self.assertIsNone(pi.content_fingerprint(self.r, "main", "main"))

    def test_sin_huella_anterior_relanza(self):
        self.assertEqual(pi.reviewers_decision(None, "abc"), ("relanzar", "sin_huella_anterior"))
        self.assertEqual(pi.reviewers_decision("", "abc"), ("relanzar", "sin_huella_anterior"))


class ClassifyHead(unittest.TestCase):
    def test_estados(self):
        c = pi.classify_head_ci
        self.assertEqual(c([]), "sin_pruebas")
        self.assertEqual(c([{"status": "QUEUED"}, {"state": "PENDING"}]), "en_cola")
        self.assertEqual(c([{"status": "QUEUED"}, {"status": "IN_PROGRESS"}]), "en_marcha")
        self.assertEqual(c([{"status": "COMPLETED", "conclusion": "SUCCESS"}]), "en_marcha")

    def test_entrada_rara_es_desconocido(self):
        c = pi.classify_head_ci
        self.assertEqual(c(None), "desconocido")
        self.assertEqual(c("x"), "desconocido")
        self.assertEqual(c([{"name": "sin estado"}]), "desconocido")
        self.assertEqual(c(["x"]), "desconocido")


class CiStep(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.led = pi.Ledger(os.path.join(self.tmp.name, "p", "ledger.jsonl"))
        self.calls = []

    def tearDown(self):
        self.tmp.cleanup()

    def relaunch(self, n):
        self.calls.append(n)

    def step(self, t, state="sin_pruebas", apply=True, relaunch=None, committed=None):
        return pi.ci_step(self.led, 9, "sha1", state, committed, t,
                          relaunch or self.relaunch, apply=apply)

    def test_flujo_completo_un_relanzamiento_y_luego_peticion(self):
        self.assertEqual(self.step(T0), ("esperar", "bajo_umbral"))
        self.assertEqual(self.step(T0 + 14 * M), ("esperar", "bajo_umbral"))
        self.assertEqual(self.calls, [])
        self.assertEqual(self.step(T0 + 15 * M), ("relanzar", "ok"))
        self.assertEqual(self.calls, [9])
        self.assertEqual(self.step(T0 + 20 * M), ("esperar", "tras_relanzar"))
        self.assertEqual(self.step(T0 + 31 * M), ("peticion", "no_arranca_tras_relanzar"))
        # NEGATIVO: nunca un segundo relanzamiento automático, ni una segunda petición
        self.assertEqual(self.step(T0 + 60 * M), ("peticion_ya_emitida", "una_por_cabeza"))
        self.assertEqual(self.calls, [9])
        kinds = [r["kind"] for r in self.led.read()]
        self.assertEqual(kinds.count("ci_relanzamiento"), 1)
        self.assertEqual(kinds.count("ci_relanzamiento_resultado"), 1)
        self.assertEqual(kinds.count("ci_atascada_peticion"), 1)

    def test_el_ledger_registra_la_causa_observada(self):
        self.step(T0)
        self.step(T0 + 15 * M, state="en_cola")
        row = self.led.find("ci_relanzamiento", 9)[0]
        self.assertEqual(row["observado"]["estado"], "en_cola")
        self.assertEqual(row["observado"]["edad_s"], 900)

    def test_si_arranca_tras_relanzar_no_hay_peticion(self):
        self.step(T0); self.step(T0 + 15 * M)
        self.assertEqual(self.step(T0 + 18 * M, state="en_marcha"), ("nada", "en_marcha"))
        self.assertEqual(len(self.led.find("ci_arrancada", 9)), 1)
        self.step(T0 + 19 * M, state="en_marcha")
        self.assertEqual(len(self.led.find("ci_arrancada", 9)), 1)
        self.assertEqual(self.led.find("ci_atascada_peticion", 9), [])

    def test_commit_antiguo_recien_visto_no_cuenta_como_atascado(self):
        old = T0 - dt.timedelta(hours=3)
        self.assertEqual(self.step(T0, committed=old), ("esperar", "bajo_umbral"))
        self.assertEqual(self.calls, [])

    def test_fallo_del_relanzamiento_cuenta_como_intento(self):
        def boom(n):
            raise RuntimeError("gh caído")
        self.step(T0)
        self.assertEqual(self.step(T0 + 15 * M, relaunch=boom), ("relanzar", "error:RuntimeError"))
        # sin segundo intento automático: tras el umbral, petición
        self.assertEqual(self.step(T0 + 31 * M, relaunch=boom)[0], "peticion")

    def test_intencion_en_ledger_antes_del_efecto(self):
        seen = []

        def spy(n):
            seen.append([r["kind"] for r in self.led.read()])
        self.step(T0); self.step(T0 + 15 * M, relaunch=spy)
        self.assertIn("ci_relanzamiento", seen[0])
        self.assertNotIn("ci_relanzamiento_resultado", seen[0])

    def test_observar_sin_apply_no_actua_ni_registra_relanzamiento(self):
        self.step(T0, apply=False)
        self.assertEqual(self.step(T0 + 15 * M, apply=False), ("observar_relanzar", "sin_pruebas"))
        self.assertEqual(self.calls, [])
        self.assertEqual(self.led.find("ci_relanzamiento", 9), [])

    def test_estado_desconocido_no_actua(self):
        self.step(T0)
        self.assertEqual(self.step(T0 + 99 * M, state="desconocido"), ("nada", "estado_desconocido"))
        self.assertEqual(self.calls, [])

    def test_otra_cabeza_es_otro_intento(self):
        self.step(T0); self.step(T0 + 15 * M)
        r = pi.ci_step(self.led, 9, "sha2", "sin_pruebas", None, T0 + 16 * M, self.relaunch)
        self.assertEqual(r, ("esperar", "bajo_umbral"))

    def test_evento_incompleto_se_rechaza(self):
        with self.assertRaises(pi.Invalid):
            self.led.append("ci_relanzamiento", T0, pr=1, sha="x", estado="")
        with self.assertRaises(pi.Invalid):
            self.led.append("tipo_inventado", T0, pr=1)
        self.assertEqual(self.led.read(), [])

    def test_ledger_corrupto_no_se_ignora(self):
        os.makedirs(os.path.dirname(self.led.path))
        with open(self.led.path, "w") as f:
            f.write("{no json\n")
        with self.assertRaises(pi.Invalid):
            self.step(T0)

    def test_ledger_solo_para_su_dueno(self):
        self.step(T0)
        self.assertEqual(stat.S_IMODE(os.stat(self.led.path).st_mode), 0o600)


FAKE_GH = r"""#!/bin/bash
echo "$@" >> "$FAKE_GH_LOG"
case "$1 $2" in
  "pr view") cat "$FAKE_GH_VIEW" ;;
  "pr close"|"pr reopen") exit "${FAKE_GH_RC:-0}" ;;
  *) exit 9 ;;
esac
"""


class Cli(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.gh = os.path.join(t, "gh")
        with open(self.gh, "w") as f:
            f.write(FAKE_GH)
        os.chmod(self.gh, 0o755)
        self.log = os.path.join(t, "gh.log")
        self.view = os.path.join(t, "view.json")
        self.ledger = os.path.join(t, "ledger.jsonl")
        self.env = dict(os.environ, GH_BIN=self.gh, FAKE_GH_LOG=self.log,
                        FAKE_GH_VIEW=self.view, PULSE_LEDGER=self.ledger)

    def tearDown(self):
        self.tmp.cleanup()

    def run_cli(self, *args, stdin=None, env=None):
        return subprocess.run([sys.executable, SCRIPT] + list(args), input=stdin,
                              capture_output=True, text=True, env=env or self.env)

    def set_view(self, checks, committed="2026-11-14T08:00:00Z"):
        with open(self.view, "w") as f:
            json.dump({"headRefOid": "abc", "statusCheckRollup": checks,
                       "commits": [{"committedDate": committed}]}, f)

    def gh_calls(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log) as f:
            return f.read().splitlines()

    def test_plan_por_stdin(self):
        r = self.run_cli("plan", "--next", "2",
                         stdin=json.dumps([pr(1, "CONFLICTING", "DIRTY"), pr(2, "MERGEABLE", "BEHIND"), pr(3, "MERGEABLE", "BEHIND")]))
        self.assertEqual(r.returncode, 0, r.stderr)
        acts = {json.loads(l)["number"]: json.loads(l)["action"] for l in r.stdout.splitlines()}
        self.assertEqual(acts, {1: "integrar", 2: "integrar", 3: "omitir"})

    def test_plan_entrada_invalida_exit_2_sin_salida(self):
        r = self.run_cli("plan", stdin="no json")
        self.assertEqual((r.returncode, r.stdout), (2, ""))
        r = self.run_cli("plan", "--policy", "siempre", stdin="[]")
        self.assertEqual((r.returncode, r.stdout), (2, ""))

    def test_ci_sin_apply_no_cierra_ni_reabre(self):
        self.set_view([])
        r = self.run_cli("ci", "--pr", "9", "--umbral", "0")
        self.assertEqual(r.returncode, 0, r.stderr)
        out = json.loads(r.stdout)
        self.assertEqual((out["action"], out["apply"]), ("observar_relanzar", False))
        self.assertFalse([c for c in self.gh_calls() if c.startswith(("pr close", "pr reopen"))])

    def test_ci_con_apply_relanza_una_vez(self):
        self.set_view([])
        # umbral 0: la primera pasada ya cumple (commit de las 08:00, visto ahora → desde=ahora)
        # por eso se hacen dos pasadas con umbral 0 para pasar por «esperar» y luego actuar.
        first = json.loads(self.run_cli("ci", "--pr", "9", "--apply", "--umbral", "0").stdout)
        second = json.loads(self.run_cli("ci", "--pr", "9", "--apply", "--umbral", "0").stdout)
        third = json.loads(self.run_cli("ci", "--pr", "9", "--apply", "--umbral", "0").stdout)
        acts = [first["action"], second["action"], third["action"]]
        self.assertEqual(acts.count("relanzar"), 1, acts)
        closes = [c for c in self.gh_calls() if c.startswith("pr close")]
        reopens = [c for c in self.gh_calls() if c.startswith("pr reopen")]
        self.assertEqual((len(closes), len(reopens)), (1, 1))

    def test_ci_respuesta_de_gh_ilegible_no_actua(self):
        with open(self.view, "w") as f:
            f.write("{}")
        r = self.run_cli("ci", "--pr", "9", "--apply")
        self.assertEqual((r.returncode, r.stdout), (2, ""))
        self.assertFalse([c for c in self.gh_calls() if c.startswith("pr close")])
        self.assertFalse(os.path.exists(self.ledger))

    def test_ci_con_pruebas_en_marcha_no_actua(self):
        self.set_view([{"name": "x", "status": "IN_PROGRESS"}])
        r = self.run_cli("ci", "--pr", "9", "--apply", "--umbral", "0")
        self.assertEqual(json.loads(r.stdout)["action"], "nada")
        self.assertFalse([c for c in self.gh_calls() if c.startswith("pr close")])

    def test_reviewers_con_git_real_y_registro(self):
        with tempfile.TemporaryDirectory() as repo:
            git(repo, "init", "-q", "-b", "main")
            write(repo, "a", "1\n"); git(repo, "add", "."); git(repo, "commit", "-qm", "b")
            git(repo, "checkout", "-qb", "pr")
            write(repo, "f", "x\n"); git(repo, "add", "."); git(repo, "commit", "-qm", "p")
            a = ["reviewers", "--repo", repo, "--pr", "5", "--base", "main", "--head", "pr", "--record"]
            r1 = json.loads(self.run_cli(*a).stdout)
            self.assertEqual((r1["action"], r1["reason"]), ("relanzar", "sin_huella_anterior"))
            r2 = json.loads(self.run_cli(*a).stdout)
            self.assertEqual((r2["action"], r2["reason"]), ("omitir", "huella_igual"))
            bad = json.loads(self.run_cli("reviewers", "--repo", repo, "--pr", "5", "--base", "main",
                                          "--head", "no-existe").stdout)
            self.assertEqual((bad["action"], bad["reason"]), ("relanzar", "huella_actual_ilegible"))


if __name__ == "__main__":
    unittest.main()
