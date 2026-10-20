#!/usr/bin/env python3
"""Prueba de savia-gates contra el motor OpenCode REAL (v2 y/o v1), sin modelo y sin red.

Un modelo falso (scripts/opencode-gates-fake-llm.py) hace que el motor emita llamadas a herramientas
de verdad; el plugin real decide. Se comprueba que carga, que bloquea (fallo cerrado) y que deja pasar.

Aislamiento: HOME, XDG_*, OPENCODE_DB y TMPDIR en un directorio temporal (la cache del motor, solo
regenerable, va a ~/.cache/savia-gates-real/<sabor>: OpenCode 1 instala ahi su SDK de proveedor la primera vez,
con red, y las siguientes ejecuciones no la necesitan); contrasena aleatoria;
`serve` explicito con puerto propio (nunca el servicio unico de v2 en 49374). No toca
~/.config/opencode ni ~/.local/share/opencode.

Uso:
  scripts/opencode-gates-real.py [--engine v2|v1|both] [--v2-bin RUTA] [--v1-bin RUTA] [--json] [--keep] [--pin] [--plugin DIR]

Salida: 0 todo bien | 1 algun fallo | 77 sin binario del motor pedido (omitido).
Binarios: v2 = --v2-bin, $OPENCODE_V2_BIN, ~/.cache/savia-space/engines/*/opencode, opencode2 o opencode
en PATH; v1 = --v1-bin, $OPENCODE_V1_BIN, opencode en PATH (si es 1.x).
"""
import argparse
import base64
import glob
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PLUGIN = os.path.join(REPO, "scripts", "opencode-plugin", "savia-gates")
FAKE_LLM = os.path.join(REPO, "scripts", "opencode-gates-fake-llm.py")
HOOKS = os.path.join(REPO, ".claude", "hooks")
MIN_V1 = (1, 18, 29)
# Clave de ejemplo de la documentacion de AWS, partida para que ningun escaner la vea en el codigo.
FAKE_AWS_KEY = "AKIA" + "IOSFODNN7" + "EXAMPLE"


def version_of(binary):
    try:
        out = subprocess.run([binary, "--version"], capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception:
        return None
    m = re.search(r"(\d+)\.(\d+)\.(\d+)", out)
    return tuple(int(x) for x in m.groups()) if m else None


def find_engine(flavor, explicit):
    major = 2 if flavor == "v2" else 1
    candidates = [explicit, os.environ.get(f"OPENCODE_{flavor.upper()}_BIN")]
    if flavor == "v2":
        candidates += sorted(glob.glob(os.path.expanduser("~/.cache/savia-space/engines/*/opencode")), reverse=True)
        candidates += [shutil.which("opencode2")]
    candidates += [shutil.which("opencode")]
    for c in candidates:
        if c and os.path.exists(c):
            v = version_of(c)
            if v and v[0] == major:
                return c, v
    return None, None


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def write(path, text, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    if mode:
        os.chmod(path, mode)


GUARD = '#!/usr/bin/env bash\nin=$(cat)\ncase "$in" in *{word}*) echo "{word} bloqueado" >&2; exit 2;; esac\nexit 0\n'
CONTEXT = ('#!/usr/bin/env bash\ncat >/dev/null\n'
           "echo '{{\"hookSpecificOutput\":{{\"hookEventName\":\"UserPromptSubmit\",\"additionalContext\":\"CTX_{lvl}\",\"saviaLevel\":\"{lvl}\"}}}}'\n")


def cmd(name):
    return {"type": "command", "command": f'"$CLAUDE_PROJECT_DIR"/.opencode/hooks/{name}'}


def make_project(root, flavor, llm_port, registry, branch="main"):
    """Proyecto git temporal con registro de hooks y el plugin cargado por la configuracion del motor."""
    os.makedirs(root, exist_ok=True)
    subprocess.run(["git", "-C", root, "init", "-q", "-b", branch], check=True)
    if registry:
        hooks_dir = os.path.join(root, ".claude", "hooks")
        for word, name in (("TOOLBLOCK", "toolguard.sh"), ("PROMPTBLOCK", "promptguard.sh")):
            write(os.path.join(hooks_dir, name), GUARD.format(word=word), 0o755)
        write(os.path.join(hooks_dir, "n3.sh"), CONTEXT.format(lvl="N3"), 0o755)
        write(os.path.join(hooks_dir, "n1.sh"), CONTEXT.format(lvl="N1"), 0o755)
        # Hooks reales del repositorio, por enlace: la misma carpeta que usa el registro de Savia.
        for real in ("block-force-push.sh", "block-credential-leak.sh", "lib"):
            os.symlink(os.path.join(HOOKS, real), os.path.join(hooks_dir, real))
        os.makedirs(os.path.join(root, ".opencode"), exist_ok=True)
        os.symlink(hooks_dir, os.path.join(root, ".opencode", "hooks"))
        write(os.path.join(root, ".claude", "settings.json"), json.dumps({"hooks": {
            "PreToolUse": [
                {"matcher": "Bash|Read|Write", "hooks": [cmd("toolguard.sh")]},
                {"matcher": "Bash", "hooks": [cmd("block-force-push.sh"), cmd("block-credential-leak.sh")]},
            ],
            "UserPromptSubmit": [{"hooks": [cmd("promptguard.sh"), cmd("n3.sh"), cmd("n1.sh")]}],
        }}))
    base = f"http://127.0.0.1:{llm_port}/v1"
    if flavor == "v2":
        cfg = {"model": "fake/m",
               "providers": {"fake": {"package": "@opencode/ai/providers/openai-compatible",
                                      "settings": {"baseURL": base, "apiKey": "x"}, "models": {"m": {}}}},
               "plugins": [{"package": PLUGIN}]}
    else:
        cfg = {"model": "fake/m", "enabled_providers": ["fake"], "plugin": [PLUGIN],
               "provider": {"fake": {"npm": "@ai-sdk/openai-compatible", "name": "fake",
                                     "options": {"baseURL": base, "apiKey": "x"},
                                     "models": {"m": {"name": "m", "tool_call": True,
                                                      "limit": {"context": 32000, "output": 2000}}}}}}
    write(os.path.join(root, "opencode.json"), json.dumps(cfg))
    return root


class Engine:
    def __init__(self, flavor, binary, work, project, extra_env, cache):
        self.flavor, self.binary, self.project = flavor, binary, project
        os.makedirs(cache, exist_ok=True)
        self.password = base64.b32encode(os.urandom(10)).decode().lower()
        self.home = os.path.join(work, "home")
        env = {k: v for k, v in os.environ.items() if not k.startswith(("OPENCODE", "SAVIA_", "XDG_"))}
        env.update({
            "HOME": self.home, "TMPDIR": os.path.join(work, "tmp"),
            "XDG_DATA_HOME": os.path.join(work, "xdg/data"), "XDG_STATE_HOME": os.path.join(work, "xdg/state"),
            "XDG_CACHE_HOME": cache, "XDG_CONFIG_HOME": os.path.join(work, "xdg/config"),
            "OPENCODE_DB": os.path.join(work, "xdg/data/opencode.db"),
            "OPENCODE_DISABLE_AUTOUPDATE": "1", "OPENCODE_DISABLE_MODELS_FETCH": "1",
            "OPENCODE_SERVER_PASSWORD": self.password,
            "SAVIA_AUDIT_DIR": os.path.join(work, "audit"),
        })
        env.update(extra_env)
        for d in (self.home, env["TMPDIR"], env["XDG_DATA_HOME"]):
            os.makedirs(d, exist_ok=True)
        self.audit = os.path.join(work, "audit", "savia-gates.jsonl")
        self.port = free_port()
        self.log = open(os.path.join(work, "serve.log"), "w")
        self.proc = subprocess.Popen(
            [binary, "serve", "--hostname", "127.0.0.1", "--port", str(self.port)],
            cwd=project, env=env, stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True)
        self.url = f"http://127.0.0.1:{self.port}"
        deadline = time.time() + 60
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError(f"el motor termino al arrancar (codigo {self.proc.returncode})")
            try:
                socket.create_connection(("127.0.0.1", self.port), timeout=1).close()
                return
            except OSError:
                time.sleep(0.2)
        raise RuntimeError("el motor no escucha tras 60 s")

    def stop(self):
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
            self.proc.wait(timeout=15)
        except Exception:
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except Exception:
                pass
        self.log.close()

    def warm(self):
        """El primer acceso levanta la instancia del proyecto (config, plugins).

        OpenCode 1.19 pierde la primera peticion si llega justo al abrir el puerto (se vio colgada
        30 s a 300 s; las siguientes responden en milisegundos): se reintenta con plazo corto.
        """
        path = "/api/session" if self.flavor == "v2" else "/session"
        for _ in range(8):
            try:
                self.call("GET", path, timeout=25)
                return
            except (TimeoutError, urllib.error.URLError, OSError):
                continue
        raise RuntimeError("el motor no atiende peticiones tras 8 intentos")

    def call(self, method, path, body=None, directory=None, timeout=120):
        headers = {"content-type": "application/json",
                   "authorization": "Basic " + base64.b64encode(f"opencode:{self.password}".encode()).decode()}
        if directory:
            headers["x-opencode-directory"] = urllib.parse.quote(directory)
        req = urllib.request.Request(self.url + path, method=method, headers=headers,
                                     data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                return r.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            return e.code, e.read().decode(errors="replace")

    def prompt(self, text, directory=None):
        if self.flavor == "v2":
            _, sess = self.call("POST", "/api/session", {}, directory)
            sid = sess["data"]["id"]
            return self.call("POST", f"/api/session/{sid}/prompt", {"text": text}, directory)[0]
        _, sess = self.call("POST", "/session", {}, directory)
        return self.call("POST", f"/session/{sess['id']}/message", {"parts": [{"type": "text", "text": text}]}, directory)[0]

    def audit_events(self):
        if not os.path.exists(self.audit):
            return []
        with open(self.audit, encoding="utf-8") as f:
            return [json.loads(line) for line in f if line.strip()]


T0 = time.time()


def progress(msg):
    print(f"[{time.time() - T0:6.1f}s] {msg}", file=sys.stderr, flush=True)


def llm_entries(log_file, marker):
    if not os.path.exists(log_file):
        return []
    with open(log_file, encoding="utf-8") as f:
        return [e for e in (json.loads(line) for line in f if line.strip()) if marker in e["user"]]


def wait_results(log_file, marker, want_results, timeout=40):
    """Espera el resultado de la herramienta; sin resultado esperado, una ventana corta y devuelve lo que haya."""
    deadline = time.time() + (timeout if want_results else 8)
    while time.time() < deadline:
        done = [r for e in llm_entries(log_file, marker) for r in e["tool_results"]]
        if done and want_results:
            return done
        time.sleep(0.4)
    return [r for e in llm_entries(log_file, marker) for r in e["tool_results"]]


def _listening(port):
    try:
        socket.create_connection(("127.0.0.1", port), timeout=1).close()
        return True
    except OSError:
        return False


def run_flavor(flavor, binary, version, keep, pin=False):
    results = []  # (nombre, ok, detalle)

    def check(name, ok, detail=""):
        results.append((f"{flavor}: {name}", bool(ok), detail))

    shell = "shell" if flavor == "v2" else "bash"
    pathkey = "path" if flavor == "v2" else "filePath"
    work = tempfile.mkdtemp(prefix=f"savia-gates-real-{flavor}-")
    cache = os.path.join(os.environ.get("SAVIA_GATES_REAL_CACHE", os.path.expanduser("~/.cache/savia-gates-real")),
                         flavor + "-" + ".".join(map(str, version)))
    llm = None
    engines = []
    try:
        llm_log = os.path.join(work, "llm.jsonl")
        port_file = os.path.join(work, "llm.port")
        llm = subprocess.Popen([sys.executable, FAKE_LLM, port_file, llm_log, "--shell-tool", shell, "--path-key", pathkey],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(50):
            if os.path.exists(port_file) and open(port_file).read().strip():
                break
            time.sleep(0.1)
        llm_port = int(open(port_file).read())

        # ---- Proyecto A: registro con guards, rama agent/* ----
        a_work = os.path.join(work, "a")
        proj = make_project(os.path.join(a_work, "proj"), flavor, llm_port, True, branch="agent/gates-test")
        os.makedirs(os.path.join(proj, "docs"), exist_ok=True)
        a_env = {"SAVIA_GATES_LOCAL_PROVIDERS": ""}
        if pin:
            a_env["SAVIA_GATES_PIN"] = "1"  # modo mediado de Space: hooks bajo bwrap desde una copia de confianza
        eng = Engine(flavor, binary, a_work, proj, a_env, cache)
        engines.append(eng)
        # Lo primero: que el plugin cargue con el sabor del motor (y no un `setup` de v2 colado bajo v1).
        progress(f"{flavor}: arranque del motor listo, calentando la instancia del proyecto")
        eng.warm()
        progress(f"{flavor}: instancia lista")
        eng.prompt("RUN: echo warmup W0")
        time.sleep(2)
        loaded = [e for e in eng.audit_events() if e["event"] == "plugin-loaded"]
        check("el plugin carga con el sabor del motor",
              any(e.get("flavor") == flavor and e["root"].endswith("/proj") for e in loaded), json.dumps(loaded)[:300])
        check("sin carga espuria (un setup de v2 bajo v1 no crea guards de mentira)",
              all(e.get("flavor") == flavor for e in loaded), json.dumps(loaded)[:300])

        def ask(text, marker, want_results=True, directory=None):
            progress(f"{flavor}: {marker} {text[:40]}")
            status = eng.prompt(text + " " + marker, directory)
            return status, wait_results(llm_log, marker, want_results)

        st, res = ask("RUN: echo TOOLBLOCK", "T1")
        check("shell con orden vetada: bloqueada y el modelo ve el fallo",
              res and "TOOLBLOCK bloqueado" in res[0] and "savia-gates" in res[0], json.dumps(res)[:300])
        check("la orden vetada no llego a ejecutarse", bool(res) and not any(r.startswith("TOOLBLOCK") for r in res), json.dumps(res)[:200])
        st, res = ask("RUN: echo fine", "T2")
        check("orden permitida: pasa", res and "fine" in res[0], json.dumps(res)[:300])
        st, res = ask("READ: /etc/TOOLBLOCK-x", "T3")
        check(f"lectura ({pathkey}) vetada: bloqueada", res and "TOOLBLOCK bloqueado" in res[0], json.dumps(res)[:300])
        st, res = ask("RUN: git push --force origin main", "T4")
        check("hook real block-force-push: git push --force bloqueado",
              res and "savia-gates" in res[0] and "force" in res[0].lower(), json.dumps(res)[:400])
        st, res = ask(f"RUN: echo {FAKE_AWS_KEY}", "T5")
        check("hook real block-credential-leak: clave AWS en la orden bloqueada",
              res and "savia-gates" in res[0], json.dumps(res)[:400])

        st, res = ask("hola PROMPTBLOCK", "P1", want_results=False)
        calls = llm_entries(llm_log, "P1")
        check("prompt vetado: no llega al modelo (fallo cerrado)", len(calls) == 0, f"http={st} llamadas={len(calls)}")
        if flavor == "v2":
            check("prompt vetado: v2 no admite el prompt (error HTTP)", st >= 400, f"http={st}")

        st, res = ask("hola", "C1", want_results=False)
        deadline = time.time() + 20
        while time.time() < deadline and not llm_entries(llm_log, "C1"):
            time.sleep(0.3)
        text = "\n".join(e["text"] for e in llm_entries(llm_log, "C1"))
        check("contexto de hooks hacia nube: solo N1 llega al modelo", "CTX_N1" in text and "CTX_N3" not in text,
              f"N1={'CTX_N1' in text} N3={'CTX_N3' in text}")

        if flavor == "v2":
            st, res = ask("RUN: git branch -D nada-que-borrar", "R1")
            check("AUTONOMOUS_REVIEWER (permission.hook evaluate): accion destructiva en agent/* denegada",
                  res and "AUTONOMOUS_REVIEWER" in res[0], json.dumps(res)[:400])
            # Una sesion abierta en un subdirectorio sigue bajo los guards del proyecto (el motor la ubica en la raiz).
            sub = os.path.join(proj, "docs")
            st, res = ask("RUN: echo TOOLBLOCK", "D1", directory=sub)
            check("sesion abierta en un subdirectorio: sigue bajo los guards", res and "TOOLBLOCK bloqueado" in res[0], json.dumps(res)[:300])

        if pin:
            st, res = ask(f"WRITE: {proj}/.claude/hooks/toolguard.sh", "G1")
            check("modo mediado (pin): editar un guard fijado se bloquea (GUARD_PROTECTED)",
                  res and "GUARD_PROTECTED" in res[0], json.dumps(res)[:300])

        eng.stop()
        check("el motor se detiene y cierra el puerto", not _listening(eng.port))

        # ---- Proyecto B: sin registro de hooks => todo cerrado ----
        b_work = os.path.join(work, "b")
        proj_b = make_project(os.path.join(b_work, "proj"), flavor, llm_port, False)
        eng_b = Engine(flavor, binary, b_work, proj_b, {}, cache)
        engines.append(eng_b)
        progress(f"{flavor}: proyecto sin registro")
        eng_b.warm()
        statusb = eng_b.prompt("hola B0")
        callsb = llm_entries(llm_log, "B0")
        check("sin registro de hooks: el prompt se bloquea (INVALID_HOOK_CONFIGURATION)", len(callsb) == 0, f"http={statusb} llamadas={len(callsb)}")
        eng_b.prompt("RUN: echo fuera B1")
        resb = wait_results(llm_log, "B1", True, timeout=15)
        check("sin registro de hooks: la herramienta no se ejecuta",
              not resb or all("fuera" not in r.split("\n")[0] for r in resb), json.dumps(resb)[:200])
        eng_b.stop()
    except Exception as e:  # noqa: BLE001
        check("la prueba termina sin excepciones", False, repr(e))
    finally:
        for e in engines:
            e.stop()
        if llm:
            try:
                os.killpg(llm.pid, signal.SIGTERM)
            except Exception:
                pass
        if keep:
            print(f"[{flavor}] conservado: {work}", file=sys.stderr)
        else:
            shutil.rmtree(work, ignore_errors=True)
    return results


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", choices=["v2", "v1", "both"], default="both")
    ap.add_argument("--v2-bin")
    ap.add_argument("--v1-bin")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--pin", action="store_true", help="SAVIA_GATES_PIN=1 (modo mediado de Space; necesita bwrap)")
    ap.add_argument("--plugin", help="directorio del plugin a probar (por defecto el del repositorio; sirve para medir una version anterior)")
    args = ap.parse_args()
    global PLUGIN
    if args.plugin:
        PLUGIN = os.path.abspath(args.plugin)

    flavors = ["v2", "v1"] if args.engine == "both" else [args.engine]
    all_results = []
    for flavor in flavors:
        binary, version = find_engine(flavor, args.v2_bin if flavor == "v2" else args.v1_bin)
        if not binary:
            print(f"OMITIDO {flavor}: no hay binario de OpenCode {flavor}", file=sys.stderr)
            continue
        if flavor == "v1" and version < MIN_V1:
            print(f"OMITIDO v1: {'.'.join(map(str, version))} < 1.18.29 (minimo del formato objeto)", file=sys.stderr)
            continue
        print(f"== {flavor}: {binary} {'.'.join(map(str, version))}", file=sys.stderr)
        all_results += run_flavor(flavor, binary, version, args.keep, args.pin)

    if args.json:
        print(json.dumps([{"name": n, "ok": ok, "detail": d} for n, ok, d in all_results], indent=1, ensure_ascii=False))
    else:
        for name, ok, detail in all_results:
            print(f"{'ok  ' if ok else 'FAIL'} {name}" + ("" if ok or not detail else f"\n       {detail}"))
    passed = sum(1 for _, ok, _ in all_results if ok)
    print(f"{passed}/{len(all_results)} comprobaciones", file=sys.stderr)
    if not all_results:
        sys.exit(77)
    sys.exit(0 if passed == len(all_results) else 1)


if __name__ == "__main__":
    main()
