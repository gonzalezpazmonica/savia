"""Primer adaptador real del contrato de ejecutores: Codex (SE-396 H09, SE-531 D2).

Cumple los cinco puertos de `AdapterRegistry` (`describe`, `preflight`, `execute`,
`cancel`, `observe`) y lanza `codex exec` con la MISMA orden que el lanzador
privado de Codex, para que el camino antiguo y este den el mismo resultado
observable. Lo que añade:

- Las capacidades que declara salen de la ficha de runtime (`contracts/runtime/
  codex.yaml`), leída con `harness_ficha.effective`: `no_medido` no concede nada.
  Hoy solo `exec.run`.
- Un código de salida 0 no es un veredicto de efecto. `succeeded` exige
  `harness_ficha.accept_exit`: con una ficha que no garantiza el código de salida,
  hace falta una postcondición OBSERVADA por el adaptador (cambio en el worktree),
  nunca lo que Codex declare en su último mensaje (eso va en `declarado`).
- Ejecutor caído (señal, plazo vencido) = `unknown`, nunca `succeeded`.
- Límite honesto: «efecto observado» es solo cambio en el worktree (`git status`
  y HEAD). Un efecto fuera del worktree no se observa. `run_dir` dentro del
  worktree se rechaza: lo que escribe el propio lanzador contaría como efecto.
- Confinamiento: se ejecuta con `workspace-write` y red, igual que el lanzador
  antiguo. La ficha deja `aislamiento: no_medido`, así que `exec.confined` no se
  concede; «no confinado» NO bloquea `exec.run`, solo impide declararlo confinado.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import stat
import subprocess
import sys
import threading
import time
from dataclasses import dataclass

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import harness_ficha  # noqa: E402
import yaml  # noqa: E402
from protocol import ProtocolError  # noqa: E402

ADAPTER_ID = "codex"
BASE_CAPABILITY = "exec.run"
_CAPABILITY_FROM_FICHA = (
    ("exec.resume", harness_ficha.can_resume),
    ("exec.group_cleanup", harness_ficha.cleanup_guaranteed),
    ("exec.call_stream", harness_ficha.watches_calls),
    ("exec.usage", harness_ficha.reports_usage),
    ("exec.confined", harness_ficha.confined),
)
LAST_MESSAGE_MAX = 4096
HASH_MAX_BYTES = 64 * 1024 * 1024  # tope por fichero al tomar la huella
EFFORTS = frozenset({"minimal", "low", "medium", "high", "xhigh"})
_MODEL_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}")


@dataclass(frozen=True)
class CodexJob:
    prompt: str
    workdir: str
    run_dir: str
    model: str
    effort: str
    add_dirs: tuple = ()
    espera_efecto: bool = False  # el encargo debe dejar cambios en el worktree


def build_argv(binary, job):
    """La orden del lanzador privado, orden a orden (prueba de equivalencia)."""
    argv = [binary, "exec", "-m", job.model, "-c", f"model_reasoning_effort={job.effort}",
            "--skip-git-repo-check", "-s", "workspace-write",
            "-c", "sandbox_workspace_write.network_access=true",
            "--add-dir", job.run_dir]
    for extra in job.add_dirs:
        argv += ["--add-dir", extra]
    return argv + ["-C", job.workdir, "-o", str(Path(job.run_dir) / "ultimo.md"), job.prompt]


def load_runtime(path):
    """Bloque `runtime` de una ficha, validado. Fail-closed: cualquier duda = error."""
    try:
        doc = yaml.load(Path(path).read_text(encoding="utf-8"), Loader=harness_ficha._UniqueLoader)  # noqa: S506
    except (OSError, UnicodeError, yaml.YAMLError, RecursionError):
        raise ProtocolError("UNSUPPORTED_SCHEMA") from None
    runtime = doc.get("runtime") if isinstance(doc, dict) else None
    if harness_ficha.validate_runtime("codex", runtime):
        raise ProtocolError("UNSUPPORTED_SCHEMA")
    return runtime


def _parse_status(raw):
    """Rutas de `git status --porcelain=v1 -z`. Un renombrado/copia (`R`/`C`) trae
    la ruta origen como entrada siguiente, SIN prefijo XY."""
    entries = raw.split(b"\0")
    out, i = [], 0
    while i < len(entries):
        e = entries[i]
        i += 1
        if len(e) < 4:
            continue
        out.append((e[:2], e[3:].decode("utf-8", "replace")))
        if e[0:1] in (b"R", b"C") or e[1:2] in (b"R", b"C"):
            if i < len(entries) and entries[i]:
                out.append((e[:2], entries[i].decode("utf-8", "replace")))
            i += 1
    return out


def _file_signature(path):
    """Huella de una ruta sin seguir enlaces ni abrir FIFOs/dispositivos."""
    try:
        st = os.lstat(path)
    except OSError:
        return "absent"
    if stat.S_ISLNK(st.st_mode):
        try:
            return "link:" + os.readlink(path)
        except OSError:
            return "link:?"
    if not stat.S_ISREG(st.st_mode):
        return f"special:{stat.S_IFMT(st.st_mode)}"
    h = hashlib.sha256(f"{st.st_size}".encode())
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | getattr(os, "O_NONBLOCK", 0))
        with os.fdopen(fd, "rb") as f:
            left = HASH_MAX_BYTES
            while left > 0:
                chunk = f.read(min(1 << 20, left))
                if not chunk:
                    break
                h.update(chunk)
                left -= len(chunk)
        if st.st_size > HASH_MAX_BYTES:  # más allá del tope: tamaño y mtime
            h.update(f"{st.st_mtime_ns}".encode())
    except OSError:
        return "unreadable"
    return h.hexdigest()


def _worktree_state(workdir):
    """(HEAD, huella del estado, {ruta: firma}) o None si no se puede observar."""
    try:
        head = subprocess.run(["git", "-C", workdir, "rev-parse", "HEAD"], capture_output=True,
                              text=True, timeout=30, check=True).stdout.strip()
        status = subprocess.run(["git", "-C", workdir, "status", "--porcelain=v1", "-z",
                                 "--untracked-files=all"], capture_output=True, timeout=30,
                                check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    sigs = {}
    for xy, name in _parse_status(status):  # el contenido cuenta: un fichero ya sucio que cambia es un efecto
        sigs[name] = xy.decode("ascii", "replace") + "|" + _file_signature(os.path.join(workdir, name))
    digest = hashlib.sha256(status)
    for name in sorted(sigs):
        digest.update(b"\0" + name.encode("utf-8", "replace") + b"\0" + sigs[name].encode())
    return head, digest.hexdigest(), sigs


def _result(request_id, state, reason, effect=None, artifacts=()):
    return {"request_id": request_id, "state": state, "reason": reason,
            "artifacts": list(artifacts), "usage": None, "external_effect_observed": effect}


class CodexAdapter:
    def __init__(self, ficha_path, jobs, *, binary=None, grace_s=5.0):
        self._runtime = load_runtime(ficha_path)
        self._jobs = dict(jobs)
        self._binary = binary if binary is not None else shutil.which("codex")
        self._grace = float(grace_s)
        self._procs = {}
        self._receipts = {}
        self._seen = set()
        self._cancelled = set()
        self._done = {}
        self._lock = threading.Lock()
        caps = [BASE_CAPABILITY] + [cid for cid, reader in _CAPABILITY_FROM_FICHA if reader(self._runtime)]
        self._capabilities = caps

    # --- puertos del contrato -------------------------------------------------
    def describe(self):
        return {"id": ADAPTER_ID, "version": "se396-h09-s1",
                "capability_ids": list(self._capabilities)}

    def _binary_ok(self):
        return bool(self._binary) and os.access(self._binary, os.X_OK) and not Path(self._binary).is_dir()

    def preflight(self, context):
        ctx = context if isinstance(context, dict) else {}
        wanted = ctx.get("capability_ids", [])
        ok = (isinstance(context, dict) and self._binary_ok() and isinstance(wanted, list)
              and all(isinstance(w, str) for w in wanted) and set(wanted).issubset(self._capabilities))
        return {"ok": ok, "request_id": ctx.get("request_id"),
                "policy_revision": ctx.get("policy_revision"), "capability_ids": wanted}

    def observe(self, request_id):
        return self._receipts.get(request_id)

    def cancel(self, request_id):
        """Síncrono: vuelve cuando el grupo ha recibido SIGTERM, gracia y SIGKILL.
        Si aún no se lanzó, queda anotado y `execute` ya no lanzará nada."""
        with self._lock:
            self._cancelled.add(request_id)
            proc = self._procs.get(request_id)
        if proc is None or proc.poll() is not None:
            return {"request_id": request_id, "state": "unknown"}
        self._kill_group(proc)
        return {"request_id": request_id, "state": "cancelled"}

    def wait(self, request_id, timeout):
        """True si `execute` de ese request terminó (y dejó recibo) dentro del plazo."""
        with self._lock:
            ev = self._done.get(request_id)
        return True if ev is None else ev.wait(timeout)

    def _kill_group(self, proc):
        """SIGTERM al grupo, gracia, SIGKILL. Un descendiente que se separó del grupo escapa (D4)."""
        for sig, wait in ((signal.SIGTERM, self._grace), (signal.SIGKILL, 5.0)):
            try:
                os.killpg(proc.pid, sig)
            except ProcessLookupError:
                return
            end = time.monotonic() + wait
            while time.monotonic() < end:
                if proc.poll() is not None:
                    try:  # el líder ha muerto: retira lo que quede del grupo
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    return
                time.sleep(0.05)

    def execute(self, request):
        rid = request["request_id"]
        blocked = self._precheck(request)
        if blocked:
            return _result(rid, "blocked", blocked, effect=False)
        done = threading.Event()
        with self._lock:
            self._done[rid] = done
        try:
            return self._run(rid, self._jobs[request["input_ref"]])
        finally:
            done.set()

    def _run(self, rid, job):
        argv = build_argv(self._binary, job)
        before = _worktree_state(job.workdir)
        log_path = Path(job.run_dir) / "log.txt"
        rc, died = None, False
        try:
            with open(log_path, "ab") as log:
                with self._lock:  # cancel no puede colarse entre la comprobación y el registro
                    if rid in self._cancelled:
                        return _result(rid, "blocked", "CANCELLED", effect=False)
                    proc = subprocess.Popen(argv, stdout=log, stderr=subprocess.STDOUT,
                                            start_new_session=True)
                    self._procs[rid] = proc
                rc = proc.wait()
        except OSError:
            died = True
        after = _worktree_state(job.workdir)
        if rc is not None and rc < 0:
            died = True
        effect = None if before is None or after is None else (before[:2] != after[:2])
        changes = ([] if before is None or after is None else  # solo lo que cambió en esta ejecución
                   sorted(n for n in set(after[2]) | set(before[2]) if before[2].get(n) != after[2].get(n)))
        last = Path(job.run_dir) / "ultimo.md"
        declared = None
        if last.is_file():
            declared = last.read_text(encoding="utf-8", errors="replace")[:LAST_MESSAGE_MAX].strip()
        artifacts = [str(p) for p in (log_path, last) if p.exists()]
        if died:
            state, reason = "unknown", "EXECUTOR_DIED"
        elif rc != 0:
            state, reason = "failed", "RC_NONZERO"
        else:
            post = (effect is True) if job.espera_efecto else None
            ok, _ = harness_ficha.accept_exit(self._runtime, rc, post)
            state, reason = ("succeeded", "RC0_ACCEPTED") if ok else ("unknown", "RC0_NOT_VERIFIED")
        self._receipts[rid] = {
            "adapter": ADAPTER_ID, "request_id": rid, "rc": rc, "argv_hash":
            hashlib.sha256(json.dumps(argv[:-1]).encode()).hexdigest(),
            "efecto_observado_en_worktree": effect, "cambios": changes,
            "declarado": {"ultimo_mensaje": declared},
            "ficha_rc_en_error": harness_ficha.effective(self._runtime, "rc_en_error"),
            "descendientes": ("sin garantia" if not harness_ficha.cleanup_guaranteed(self._runtime)
                              else "grupo retirado"),
        }
        return _result(rid, state, reason, effect=effect, artifacts=artifacts)

    def _precheck(self, request):
        if request["external_effect_intent"]:
            return "EXTERNAL_EFFECT"
        needed = {request["capability_id"], *request["required_capabilities"]}
        if not needed.issubset(self._capabilities):
            return "UNSUPPORTED_CAPABILITY"
        job = self._jobs.get(request["input_ref"])
        if job is None:
            return "UNKNOWN_INPUT"
        if not self._binary_ok():
            return "BINARY_MISSING"
        if not isinstance(job.prompt, str) or not job.prompt or job.prompt.startswith("-"):
            return "UNSAFE_PROMPT"  # el lanzador antiguo pasa el prompt sin `--`
        if not _safe_args(job):
            return "UNSAFE_ARGUMENT"
        if _inside(job.run_dir, job.workdir):
            return "RUN_DIR_IN_WORKTREE"  # log.txt y ultimo.md contarían como efecto
        with self._lock:
            if request["request_id"] in self._cancelled:
                return "CANCELLED"
            if request["request_id"] in self._seen:
                return "ALREADY_EXECUTED"
            self._seen.add(request["request_id"])
        return None


def _safe_args(job):
    """Lista blanca: nada que empiece por `-` ni sintaxis TOML en `-c`."""
    if not isinstance(job.effort, str) or job.effort not in EFFORTS:
        return False
    if not isinstance(job.model, str) or not _MODEL_RE.fullmatch(job.model):
        return False
    paths = (job.workdir, job.run_dir, *job.add_dirs)
    return all(isinstance(x, str) and x and not x.startswith("-") and "\0" not in x for x in paths)


def _inside(child, parent):
    try:
        c, p = Path(child).resolve(), Path(parent).resolve()
    except (OSError, RuntimeError):
        return True  # sin poder resolver, se trata como dentro (fail-closed)
    return c == p or p in c.parents
