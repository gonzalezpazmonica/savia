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
  y HEAD). Un efecto fuera del worktree no se observa.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
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


def _worktree_state(workdir):
    """(HEAD, huella del estado) o None si no se puede observar."""
    try:
        head = subprocess.run(["git", "-C", workdir, "rev-parse", "HEAD"], capture_output=True,
                              text=True, timeout=30, check=True).stdout.strip()
        status = subprocess.run(["git", "-C", workdir, "status", "--porcelain=v1", "-z",
                                 "--untracked-files=all"], capture_output=True, timeout=30,
                                check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    files = [e[3:].decode("utf-8", "replace") for e in status.split(b"\0") if e]
    digest = hashlib.sha256(status)
    for name in sorted(files):  # el contenido cuenta: un fichero ya sucio que cambia es un efecto
        try:
            digest.update(Path(workdir, name).read_bytes())
        except OSError:
            digest.update(b"\0absent")
    return head, digest.hexdigest(), sorted(files)


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
        wanted = context.get("capability_ids", []) if isinstance(context, dict) else []
        ok = (self._binary_ok() and isinstance(wanted, list)
              and set(wanted).issubset(self._capabilities))
        return {"ok": ok, "request_id": context.get("request_id"),
                "policy_revision": context.get("policy_revision"), "capability_ids": wanted}

    def observe(self, request_id):
        return self._receipts.get(request_id)

    def cancel(self, request_id):
        with self._lock:
            proc = self._procs.get(request_id)
        if proc is None or proc.poll() is not None:
            return {"request_id": request_id, "state": "unknown"}
        self._kill_group(proc)
        return {"request_id": request_id, "state": "cancelled"}

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
        job = self._jobs[request["input_ref"]]
        argv = build_argv(self._binary, job)
        before = _worktree_state(job.workdir)
        log_path = Path(job.run_dir) / "log.txt"
        rc, died = None, False
        try:
            with open(log_path, "ab") as log:
                proc = subprocess.Popen(argv, stdout=log, stderr=subprocess.STDOUT,
                                        start_new_session=True)
                with self._lock:
                    self._procs[rid] = proc
                rc = proc.wait()
        except OSError:
            died = True
        after = _worktree_state(job.workdir)
        if rc is not None and rc < 0:
            died = True
        effect = None if before is None or after is None else (before[:2] != after[:2])
        changes = [] if before is None or after is None else sorted(set(after[2]) | set(before[2]))
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
        with self._lock:
            if request["request_id"] in self._seen:
                return "ALREADY_EXECUTED"
            self._seen.add(request["request_id"])
        return None
