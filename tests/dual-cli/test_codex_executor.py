"""SE-396 H09 / SE-531 D2: primer adaptador real del contrato de ejecutores (Codex).

Todas las pruebas usan un Codex SIMULADO (un script que registra su argv y se
comporta según el prompt). Ninguna llama al proveedor.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import textwrap
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
CORE = ROOT / "scripts/dual-cli"
sys.path.insert(0, str(CORE))
sys.path.insert(0, str(ROOT / "scripts"))
from contracts import AdapterRegistry, execution_request, execution_result  # noqa: E402
from protocol import ProtocolError  # noqa: E402
import codex_executor as ce  # noqa: E402
from runtime import _execute_with_deadline  # noqa: E402

FICHA_REAL = ROOT / "contracts/runtime/codex.yaml"

FAKE = textwrap.dedent("""\
    #!/usr/bin/env python3
    import json, os, signal, subprocess, sys, time
    argv = sys.argv[1:]
    prompt = argv[-1]
    log = os.environ.get("FAKE_CODEX_LOG")
    if log:
        with open(log, "a") as f:
            f.write(json.dumps(argv) + "\\n")
    out = argv[argv.index("-o") + 1] if "-o" in argv else None
    cwd = argv[argv.index("-C") + 1] if "-C" in argv else os.getcwd()
    print("fake-codex stdout")
    print("fake-codex stderr", file=sys.stderr)
    if "MODO:ok" in prompt:
        open(os.path.join(cwd, "producto.txt"), "w").write("hecho\\n")
        if out: open(out, "w").write("ESTADO: OK\\n")
        sys.exit(0)
    if "MODO:rc0-sin-efecto" in prompt:
        if out: open(out, "w").write("ESTADO: OK\\n")   # lo DECLARA, no hace nada
        sys.exit(0)
    if "MODO:fallo" in prompt:
        open(os.path.join(cwd, "parcial.txt"), "w").write("a medias\\n")
        sys.exit(3)
    if "MODO:caida" in prompt:
        os.kill(os.getpid(), signal.SIGKILL)
    if "MODO:cuelga" in prompt:
        nieto = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
        open(os.environ["FAKE_CODEX_PIDS"], "w").write(f"{os.getpid()} {nieto.pid}")
        time.sleep(60)
    if "MODO:ignora-term" in prompt:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        open(os.environ["FAKE_CODEX_PIDS"], "w").write(f"{os.getpid()}")
        time.sleep(60)
    sys.exit(9)
""")


def vivo(pid):
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    try:  # un zombi cuenta como muerto
        return Path(f"/proc/{pid}/stat").read_text().split(")")[-1].split()[0] != "Z"
    except OSError:
        return False


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.codex = self.bin / "codex"
        self.codex.write_text(FAKE)
        self.codex.chmod(0o755)
        self.wt = self.root / "wt"
        self.run_dir = self.root / "run"
        self.run_dir.mkdir()
        subprocess.run(["git", "-C", str(self.root), "init", "-q", str(self.wt)], check=True)
        for k, v in (("user.email", "t@t"), ("user.name", "t")):
            subprocess.run(["git", "-C", str(self.wt), "config", k, v], check=True)
        (self.wt / "base.txt").write_text("base\n")
        subprocess.run(["git", "-C", str(self.wt), "add", "."], check=True)
        subprocess.run(["git", "-C", str(self.wt), "commit", "-q", "-m", "base"], check=True)
        self.argv_log = self.root / "argv.log"
        self.pids = self.root / "pids.txt"
        os.environ["FAKE_CODEX_LOG"] = str(self.argv_log)
        os.environ["FAKE_CODEX_PIDS"] = str(self.pids)
        self.addCleanup(os.environ.pop, "FAKE_CODEX_LOG", None)
        self.addCleanup(os.environ.pop, "FAKE_CODEX_PIDS", None)
        self.addCleanup(self.limpiar_procesos)

    def limpiar_procesos(self):
        if self.pids.exists():
            for pid in map(int, self.pids.read_text().split()):
                try:
                    os.kill(pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass

    def job(self, prompt, **kw):
        kw.setdefault("add_dirs", ())
        return ce.CodexJob(prompt=prompt, workdir=str(self.wt), run_dir=str(self.run_dir),
                           model="modelo-x", effort="low", **kw)

    def adapter(self, job, ficha=FICHA_REAL, **kw):
        return ce.CodexAdapter(ficha, {"in": job}, binary=str(self.codex), **kw)

    def request(self, **kw):
        base = {"request_id": "r1", "capability_id": "exec.run", "context_ref": "ctx",
                "scope_ref": "scope", "input_ref": "in", "required_capabilities": [],
                "deadline_ms": 20000, "external_effect_intent": False}
        base.update(kw)
        return execution_request(base)

    def ficha_medida(self, **campos):
        import yaml
        runtime = {"aislamiento": "ninguno", "rc_en_error": "fiable", "senal_cuota": "ninguna",
                   "informa_uso": "no", "reanudacion": "no_soportada", "limpieza": "ninguna",
                   "flujo_llamadas": "ninguno"}
        runtime.update(campos)
        medidos = [k for k, v in runtime.items() if v != "no_medido"]
        runtime["fuente"] = {k: "prueba-sintetica" for k in medidos}
        runtime["version_cli"] = {k: "0.0.0" for k in medidos}
        path = self.root / "codex.yaml"
        path.write_text(yaml.safe_dump({"ficha": "codex", "runtime": runtime}))
        return path


class Capacidades(Base):
    def test_descriptor_de_la_ficha_real_solo_declara_ejecutar(self):
        a = self.adapter(self.job("MODO:ok"))
        self.assertEqual(a.describe()["capability_ids"], ["exec.run"])
        AdapterRegistry([a])  # cumple los cinco puertos del contrato

    def test_capacidad_no_declarada_se_rechaza_sin_lanzar_codex(self):
        a = self.adapter(self.job("MODO:ok"))
        res = a.execute(self.request(required_capabilities=["exec.resume"]))
        execution_result(res)
        self.assertEqual(res["state"], "blocked")
        self.assertEqual(res["reason"], "UNSUPPORTED_CAPABILITY")
        self.assertFalse(self.argv_log.exists(), "no debe lanzarse Codex")
        self.assertFalse(a.preflight({"request_id": "r1", "policy_revision": "p",
                                      "capability_ids": ["exec.resume"]})["ok"])

    def test_capacidad_declarada_en_la_ficha_si_se_acepta(self):
        a = self.adapter(self.job("MODO:ok"), ficha=self.ficha_medida(reanudacion="por_sesion"))
        self.assertIn("exec.resume", a.describe()["capability_ids"])
        pre = a.preflight({"request_id": "r1", "policy_revision": "p",
                           "capability_ids": ["exec.resume"]})
        self.assertTrue(pre["ok"])

    def test_no_medido_nunca_da_capacidad(self):
        a = self.adapter(self.job("MODO:ok"), ficha=self.ficha_medida(reanudacion="no_medido"))
        self.assertNotIn("exec.resume", a.describe()["capability_ids"])

    def test_valor_fuera_del_esquema_no_construye_el_adaptador(self):
        with self.assertRaises(ProtocolError):
            self.adapter(self.job("MODO:ok"), ficha=self.ficha_medida(limpieza="no_soportada"))

    def test_ficha_invalida_no_construye_el_adaptador(self):
        mala = self.root / "codex.yaml"
        mala.write_text("ficha: codex\nruntime:\n  aislamiento: casi\n")
        with self.assertRaises(ProtocolError):
            ce.CodexAdapter(mala, {}, binary=str(self.codex))

    def test_ficha_ausente_no_construye_el_adaptador(self):
        with self.assertRaises(ProtocolError):
            ce.CodexAdapter(self.root / "no-existe.yaml", {}, binary=str(self.codex))


class Recibo(Base):
    def test_rc0_con_efecto_observado_es_succeeded_y_el_recibo_separa_lo_declarado(self):
        a = self.adapter(self.job("MODO:ok", espera_efecto=True))
        res = a.execute(self.request())
        execution_result(res)
        self.assertEqual(res["state"], "succeeded")
        self.assertIs(res["external_effect_observed"], True)
        rec = a.observe("r1")
        self.assertEqual(rec["rc"], 0)
        self.assertIs(rec["efecto_observado_en_worktree"], True)
        self.assertEqual(rec["declarado"]["ultimo_mensaje"], "ESTADO: OK")
        self.assertIn("producto.txt", rec["cambios"])

    def test_rc0_sin_efecto_no_es_succeeded_aunque_lo_declare(self):
        a = self.adapter(self.job("MODO:rc0-sin-efecto", espera_efecto=True))
        res = a.execute(self.request())
        self.assertEqual(res["state"], "unknown")
        self.assertEqual(res["reason"], "RC0_NOT_VERIFIED")
        self.assertIs(res["external_effect_observed"], False)

    def test_rc0_sin_postcondicion_con_ficha_no_medida_es_unknown(self):
        a = self.adapter(self.job("MODO:ok"))  # no declara espera_efecto: nadie verifica
        res = a.execute(self.request())
        self.assertEqual(res["state"], "unknown")
        self.assertEqual(res["reason"], "RC0_NOT_VERIFIED")

    def test_rc0_con_ficha_fiable_se_acepta_sin_postcondicion(self):
        a = self.adapter(self.job("MODO:rc0-sin-efecto"), ficha=self.ficha_medida(rc_en_error="fiable"))
        self.assertEqual(a.execute(self.request())["state"], "succeeded")

    def test_rc_distinto_de_cero_es_failed_y_registra_el_efecto_parcial(self):
        a = self.adapter(self.job("MODO:fallo"))
        res = a.execute(self.request())
        self.assertEqual(res["state"], "failed")
        self.assertIs(res["external_effect_observed"], True)
        self.assertEqual(a.observe("r1")["rc"], 3)

    def test_ejecutor_caido_deja_estado_desconocido_nunca_completado(self):
        a = self.adapter(self.job("MODO:caida", espera_efecto=True))
        res = a.execute(self.request())
        execution_result(res)
        self.assertEqual(res["state"], "unknown")
        self.assertEqual(res["reason"], "EXECUTOR_DIED")
        self.assertNotEqual(res["state"], "succeeded")

    def test_binario_ausente_no_lanza_nada_y_no_dice_succeeded(self):
        a = ce.CodexAdapter(FICHA_REAL, {"in": self.job("MODO:ok")}, binary=str(self.root / "no-hay"))
        self.assertFalse(a.preflight({"request_id": "r1", "policy_revision": "p",
                                      "capability_ids": ["exec.run"]})["ok"])
        res = a.execute(self.request())
        self.assertEqual(res["state"], "blocked")
        self.assertEqual(res["reason"], "BINARY_MISSING")

    def test_entrada_sin_trabajo_registrado_se_bloquea(self):
        a = self.adapter(self.job("MODO:ok"))
        res = a.execute(self.request(input_ref="otro"))
        self.assertEqual(res["state"], "blocked")
        self.assertEqual(res["reason"], "UNKNOWN_INPUT")
        self.assertFalse(self.argv_log.exists())

    def test_prompt_que_empieza_por_guion_se_bloquea(self):
        a = self.adapter(self.job("--version"))
        res = a.execute(self.request())
        self.assertEqual(res["state"], "blocked")
        self.assertEqual(res["reason"], "UNSAFE_PROMPT")
        self.assertFalse(self.argv_log.exists())

    def test_peticion_con_efecto_externo_se_bloquea(self):
        a = self.adapter(self.job("MODO:ok"))
        res = a.execute(self.request(external_effect_intent=True))
        self.assertEqual(res["state"], "blocked")
        self.assertEqual(res["reason"], "EXTERNAL_EFFECT")
        self.assertFalse(self.argv_log.exists())

    def test_un_mismo_request_id_no_se_ejecuta_dos_veces(self):
        a = self.adapter(self.job("MODO:ok", espera_efecto=True))
        a.execute(self.request())
        res = a.execute(self.request())
        self.assertEqual(res["state"], "blocked")
        self.assertEqual(res["reason"], "ALREADY_EXECUTED")
        self.assertEqual(len(self.argv_log.read_text().splitlines()), 1)


class Plazo(Base):
    def test_plazo_vencido_es_ambiguo_y_cancel_retira_el_grupo_de_procesos(self):
        a = self.adapter(self.job("MODO:cuelga", espera_efecto=True), grace_s=0.5)
        t0 = time.monotonic()
        with self.assertRaises(ProtocolError) as cm:
            _execute_with_deadline(a, self.request(deadline_ms=1500))
        self.assertEqual(cm.exception.code, "AMBIGUOUS_EXECUTION")
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and any(vivo(p) for p in map(int, self.pids.read_text().split())):
            time.sleep(.1)
        hijo, nieto = map(int, self.pids.read_text().split())
        self.assertFalse(vivo(hijo), "el hijo debe estar muerto")
        self.assertFalse(vivo(nieto), "el nieto del mismo grupo debe estar muerto")
        self.assertLess(time.monotonic() - t0, 15)

    def test_quien_ignora_sigterm_muere_por_sigkill_tras_la_gracia(self):
        a = self.adapter(self.job("MODO:ignora-term"), grace_s=0.5)
        with self.assertRaises(ProtocolError):
            _execute_with_deadline(a, self.request(deadline_ms=1500))
        pid = int(self.pids.read_text())
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline and vivo(pid):
            time.sleep(.1)
        self.assertFalse(vivo(pid))

    def test_cancel_de_un_request_desconocido_no_mata_nada(self):
        a = self.adapter(self.job("MODO:ok"))
        self.assertEqual(a.cancel("nadie")["state"], "unknown")


class Equivalencia(Base):
    """Mismo encargo por el camino antiguo (argv de lanzar-codex) y por el adaptador."""

    def argv_antiguo(self, job, binary):
        # Reproduce, orden a orden, la orden que arma el lanzador privado:
        #   codex exec -m M -c model_reasoning_effort=E --skip-git-repo-check -s workspace-write
        #     -c sandbox_workspace_write.network_access=true --add-dir L --add-dir GD -C W -o L/ultimo.md P
        gd = subprocess.run(["git", "-C", job.workdir, "rev-parse", "--path-format=absolute",
                             "--git-common-dir"], capture_output=True, text=True, check=True).stdout.strip()
        return [binary, "exec", "-m", job.model, "-c", f"model_reasoning_effort={job.effort}",
                "--skip-git-repo-check", "-s", "workspace-write",
                "-c", "sandbox_workspace_write.network_access=true",
                "--add-dir", job.run_dir, "--add-dir", gd, "-C", job.workdir,
                "-o", str(Path(job.run_dir) / "ultimo.md"), job.prompt]

    def test_argv_identico_al_del_lanzador_antiguo(self):
        gd = subprocess.run(["git", "-C", str(self.wt), "rev-parse", "--path-format=absolute",
                             "--git-common-dir"], capture_output=True, text=True, check=True).stdout.strip()
        job = self.job("MODO:ok", add_dirs=(gd,))
        self.assertEqual(ce.build_argv(str(self.codex), job), self.argv_antiguo(job, str(self.codex)))

    def test_mismo_resultado_observable_por_ambos_caminos(self):
        gd = subprocess.run(["git", "-C", str(self.wt), "rev-parse", "--path-format=absolute",
                             "--git-common-dir"], capture_output=True, text=True, check=True).stdout.strip()
        # camino antiguo
        job_a = self.job("MODO:ok", add_dirs=(gd,))
        with open(Path(self.run_dir) / "log.txt", "ab") as log:
            rc_antiguo = subprocess.run(self.argv_antiguo(job_a, str(self.codex)), stdout=log,
                                        stderr=subprocess.STDOUT, timeout=30).returncode
        antiguo = {"rc": rc_antiguo,
                   "ultimo": (Path(self.run_dir) / "ultimo.md").read_text(),
                   "log": (Path(self.run_dir) / "log.txt").read_text(),
                   "efecto": (self.wt / "producto.txt").read_text()}
        # reinicio del escenario
        (self.wt / "producto.txt").unlink()
        (Path(self.run_dir) / "ultimo.md").unlink()
        (Path(self.run_dir) / "log.txt").unlink()
        self.argv_log.unlink()
        # camino nuevo
        job_b = self.job("MODO:ok", add_dirs=(gd,), espera_efecto=True)
        res = self.adapter(job_b).execute(self.request())
        nuevo = {"rc": 0 if res["state"] == "succeeded" else 99,
                 "ultimo": (Path(self.run_dir) / "ultimo.md").read_text(),
                 "log": (Path(self.run_dir) / "log.txt").read_text(),
                 "efecto": (self.wt / "producto.txt").read_text()}
        self.assertEqual(antiguo, nuevo)

    def test_el_log_se_anade_no_se_trunca(self):
        (Path(self.run_dir) / "log.txt").write_text("previo\n")
        self.adapter(self.job("MODO:ok", espera_efecto=True)).execute(self.request())
        texto = (Path(self.run_dir) / "log.txt").read_text()
        self.assertTrue(texto.startswith("previo\n"))
        self.assertIn("fake-codex stdout", texto)


class PuntoDeLlamada(Base):
    """`codex_launch.py`: lo que llamaría lanzar-codex en lugar de `timeout … codex exec`."""

    def lanzar(self, prompt, *extra, horas="0.001"):
        pf = self.root / "prompt.md"
        pf.write_text(prompt)
        env = {**os.environ, "PATH": f"{self.bin}:{os.environ['PATH']}"}
        return subprocess.run(
            [sys.executable, str(CORE / "codex_launch.py"), "--worktree", str(self.wt),
             "--run-dir", str(self.run_dir), "--prompt-file", str(pf), "--model", "modelo-x",
             "--effort", "low", "--hours", horas, "--espera-efecto", *extra],
            capture_output=True, text=True, env=env, timeout=60)

    def test_ok_sale_0_y_deja_recibo_json(self):
        p = self.lanzar("MODO:ok", horas="0.01")
        self.assertEqual(p.returncode, 0, p.stderr)
        rec = json.loads((self.run_dir / "recibo.json").read_text())
        self.assertEqual(rec["resultado"]["state"], "succeeded")
        self.assertIs(rec["observado"]["efecto_observado_en_worktree"], True)
        self.assertTrue((self.run_dir / "ultimo.md").exists())

    def test_rc0_sin_efecto_no_sale_0(self):
        p = self.lanzar("MODO:rc0-sin-efecto", horas="0.01")
        self.assertEqual(p.returncode, 3, p.stderr)  # 3 = desconocido
        rec = json.loads((self.run_dir / "recibo.json").read_text())
        self.assertEqual(rec["resultado"]["state"], "unknown")

    def test_fallo_sale_1(self):
        self.assertEqual(self.lanzar("MODO:fallo", horas="0.01").returncode, 1)

    def test_plazo_vencido_sale_3_y_recibo_ambiguo(self):
        p = self.lanzar("MODO:cuelga", "--grace", "0.5", horas="0.0005")
        self.assertEqual(p.returncode, 3, p.stderr)
        rec = json.loads((self.run_dir / "recibo.json").read_text())
        self.assertEqual(rec["resultado"]["state"], "unknown")
        self.assertEqual(rec["resultado"]["reason"], "AMBIGUOUS_EXECUTION")

    def test_sin_codex_en_path_sale_4_bloqueado(self):
        pf = self.root / "prompt.md"
        pf.write_text("MODO:ok")
        env = {**os.environ, "PATH": "/nonexistent"}
        p = subprocess.run(
            [sys.executable, str(CORE / "codex_launch.py"), "--worktree", str(self.wt),
             "--run-dir", str(self.run_dir), "--prompt-file", str(pf), "--model", "m",
             "--effort", "low", "--hours", "1"], capture_output=True, text=True, env=env, timeout=30)
        self.assertEqual(p.returncode, 4)
        self.assertEqual(json.loads((self.run_dir / "recibo.json").read_text())["resultado"]["reason"],
                         "BINARY_MISSING")


if __name__ == "__main__":
    unittest.main()
