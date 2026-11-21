#!/usr/bin/env python3
"""savia-control.py — plano de control local por instalación (SE-498 F0).

Estado (state.json), época de revocación monótona, stop_seq, diario encadenado
(control.jsonl), marca de instalación fuera del directorio de control y las cinco
operaciones: pause, revoke, quarantine, reconcile, resume. Además check, status,
epoch y publish-epoch. Python stdlib; se invoca con `python3 -I`.

Códigos de salida (R3): 0 éxito · 2 uso o fuente local ilegible · 3 status incompleto ·
4 resume sin aprobación válida · 5 en vuelo sin cerrar · 6 check parado ·
8 check con época de grant inválida · 9 resume cubierto por otra entrada.

Fuera de F0 (no implementado aquí): adaptadores concretos (F1), gate de frontend (F2),
integración con SE-493 y SE-496 (F3). `reconcile` lee un ledger JSONL si existe; la
transición `abandon` necesita `scripts/effect-ledger.py` y, sin él, el efecto queda
INDETERMINATE (fail-closed).
"""
import argparse
import fcntl
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import time

VERSION = 1
RANK = {"RUNNING": 0, "PAUSED": 1, "QUARANTINED": 2, "REVOKED": 3}
STOP_MODES = ("PAUSED", "QUARANTINED", "REVOKED")
ID_RE = re.compile(r"[A-Za-z0-9._-]{1,64}")  # siempre con fullmatch: $ admite un \n final
EPOCH_RE = re.compile(r"[0-9]{1,9}\n?")  # siempre con fullmatch
LOGIN_RE = re.compile(r"[A-Za-z0-9-]{1,39}")  # siempre con fullmatch
EPOCH_PATH = "config/control/REVOCATION_EPOCH"
REMOTE_PATH = "config/control/executors-remote.json"
OPERATOR_PATH = "config/control/operator.json"
RESUME_DIR = "config/control/resume"
EPOCH_CHECK = "control-epoch-monotonic"
ACTIONS_APP_ID = 15368  # app «GitHub Actions»: fuente del check obligatorio de época
STATE_KEYS = {"version", "epoch", "stop_seq", "stops"}
ENTRY_KEYS = {"mode", "stop_seq", "since", "reason", "actor"}
FORBIDDEN_ANCESTORS = {"claude", "opencode", "script"}
PINNED_PATHS = {"effect_ledger": ("SAVIA_EFFECT_LEDGER", (".savia", "effect-ledger", "ledger.jsonl")),
                "merge_sprint_home": ("MERGE_SPRINT_HOME", (".savia", "merge-sprint"))}
SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))
# Variables de Git que redirigen qué repositorio, índice, objetos o configuración usa un subproceso. `git -C` no las
# anula: con GIT_DIR ajeno, `check` leería la marca de otro repo y daría RUNNING. Se descartan al arrancar.
GIT_REDIRECT_VARS = ("GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY",
                     "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_NAMESPACE", "GIT_PREFIX", "GIT_CEILING_DIRECTORIES",
                     "GIT_DISCOVERY_ACROSS_FILESYSTEM", "GIT_CONFIG", "GIT_CONFIG_COUNT", "GIT_CONFIG_PARAMETERS",
                     "GIT_EXEC_PATH", "GIT_REPLACE_REF_BASE", "GIT_NO_REPLACE_OBJECTS", "GIT_SHALLOW_FILE",
                     "GIT_GRAFT_FILE", "GIT_CONFIG_GLOBAL", "GIT_CONFIG_SYSTEM")
# Variables de gh que cambian contra qué repositorio o servidor se consulta: con GH_REPO ajeno, las reglas de main,
# las PR y el merged_by de verify_pr vendrían de un repo del atacante. Se conservan las credenciales (GH_TOKEN,
# GH_CONFIG_DIR) y la red (HTTPS_PROXY, SSL_CERT_FILE). Esto NO es una barrera frente a un proceso con el mismo UID:
# con GH_CONFIG_DIR, un proxy o un certificado propios puede fabricar respuestas, igual que puede reescribir
# state.json. Esa barrera es condición de F2 (estado y verificación fuera del alcance del ejecutor).
GH_REDIRECT_VARS = ("GH_REPO", "GH_HOST")


def scrub_git_env(env=None):
    env = os.environ if env is None else env
    for k in list(env):
        if k in GIT_REDIRECT_VARS or k in GH_REDIRECT_VARS or re.fullmatch(r"GIT_CONFIG_(KEY|VALUE)_[0-9]+", k):
            del env[k]
    return env


scrub_git_env()


class Fail(Exception):
    def __init__(self, code, msg):
        super().__init__(msg)
        self.code, self.msg = code, msg


def out(msg):
    print(msg, flush=True)


# ── utilidades ──────────────────────────────────────────────────────────────

def run(cmd, cwd=None, timeout=30, inp=None):
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, errors="replace",
                           timeout=timeout, input=inp)
        return r.returncode, r.stdout, r.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 127, "", str(e)


def sha256(data):
    return hashlib.sha256(data if isinstance(data, bytes) else data.encode()).hexdigest()


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def atomic_write(path, text):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    with os.fdopen(fd, "w") as f:
        f.write(text)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)
    dfd = os.open(d, os.O_RDONLY)
    try:
        os.fsync(dfd)
    finally:
        os.close(dfd)


def nat(v):
    """Entero >= 0 de verdad: True/False no cuentan como 1/0."""
    return isinstance(v, int) and not isinstance(v, bool) and v >= 0


def valid_scope(s):
    if s == "global":
        return True
    kind, sep, ident = s.partition(":")
    return bool(sep) and kind in ("executor", "principal", "contract") and bool(ID_RE.fullmatch(ident))


def ancestors(full=False):
    """Cadena de ancestros desde el padre hasta el PID 1. None si no se puede leer."""
    chain, pid = [], os.getppid()
    try:
        while pid > 0:
            with open(f"/proc/{pid}/comm") as f:
                comm = f.read().strip()
            item = {"pid": pid, "comm": comm}
            if full:
                with open(f"/proc/{pid}/cmdline", "rb") as f:
                    item["cmdline"] = [a.decode(errors="replace") for a in f.read().split(b"\0") if a]
            chain.append(item)
            if pid == 1:
                break
            ppid = None
            with open(f"/proc/{pid}/status") as f:
                for line in f:
                    if line.startswith("PPid:"):
                        ppid = int(line.split()[1])
            if ppid is None:
                return None
            pid = ppid
    except (OSError, ValueError):
        return None
    return chain


def actor():
    chain = ancestors() or []
    return {"declared": os.environ.get("SAVIA_ACTOR", ""), "uid": os.getuid(), "pid": os.getpid(),
            "ancestors": [f"{a['pid']}:{a['comm']}" for a in chain]}


# ── contexto: marca, directorio, diario, estado, época ──────────────────────

class Ctx:
    def __init__(self):
        rc, common, _ = run(["git", "-C", SCRIPT_DIR, "rev-parse", "--git-common-dir"])
        rc2, top, _ = run(["git", "-C", SCRIPT_DIR, "rev-parse", "--show-toplevel"])
        if rc or rc2 or not common.strip() or not top.strip():
            raise Fail(2, "MARK_UNRESOLVABLE: savia-control.py no está en un checkout de git (o falta git)")
        common = common.strip()
        if not os.path.isabs(common):
            common = os.path.join(SCRIPT_DIR, common)
        self.root = top.strip()
        self.marker_path = os.path.join(os.path.realpath(common), "savia-control", "installed")
        self.marker = None
        if os.path.exists(self.marker_path):
            try:
                with open(self.marker_path) as f:
                    m = json.load(f)
                assert isinstance(m, dict) and isinstance(m.get("control_dir"), str)
                assert nat(m.get("epoch_hwm")) and nat(m.get("stop_seq_hwm"))
                assert isinstance(m.get("consumed"), list)
                assert all(isinstance(m.get(k), str) for k in PINNED_PATHS if k in m)
                self.marker = m
            except (OSError, ValueError, AssertionError):
                raise Fail(2, f"MARK_UNREADABLE: {self.marker_path}")
        env = os.environ.get("SAVIA_CONTROL_DIR")
        if self.marker:
            self.cdir = self.marker["control_dir"]
            if env and os.path.realpath(env) != os.path.realpath(self.cdir):
                raise Fail(2, "CONTROL_DIR_MISMATCH: SAVIA_CONTROL_DIR no coincide con la marca de instalación")
        else:
            self.cdir = env or os.path.join(os.path.expanduser("~"), ".savia", "control")
        self.cdir = os.path.realpath(self.cdir)
        # Ledger de efectos y del merge-sprint: como el directorio de control, quedan fijados en la marca. Si no, una
        # variable de entorno vaciaría el ledger de reconcile o saltaría la comprobación MERGED_BY_SPRINT.
        self.paths = {}
        for key, (var, default) in PINNED_PATHS.items():
            pinned, envv = (self.marker or {}).get(key), os.environ.get(var)
            if pinned is not None and envv and os.path.realpath(envv) != os.path.realpath(pinned):
                raise Fail(2, f"PATH_MISMATCH: {var} no coincide con la marca de instalación")
            self.paths[key] = os.path.realpath(pinned or envv or os.path.join(os.path.expanduser("~"), *default))
        self.state_path = os.path.join(self.cdir, "state.json")
        self.journal_path = os.path.join(self.cdir, "control.jsonl")
        self.warnings = []
        self.journal = self._load_journal()
        self.origin_epoch = self._origin_epoch()
        self._load_state()

    # diario encadenado
    def _load_journal(self):
        if not os.path.exists(self.journal_path):
            return None
        recs, prev = [], "genesis"
        self._journal_cut = None
        try:
            with open(self.journal_path, "rb") as f:
                data = f.read()
            cut = data.rfind(b"\n") + 1
            body, tail = data[:cut], data[cut:]
            if tail:
                # Última línea sin \n final: un append interrumpido (crash, ENOSPC) o en curso. Solo esa se
                # ignora; begin_write la aparta antes de escribir. Cualquier otra línea rota sigue siendo exit 2.
                self._journal_cut = cut
                self.warnings.append("JOURNAL_TRUNCATED_TAIL")
            for raw in body.splitlines():
                if not raw.strip():
                    continue
                rec = json.loads(raw)
                if not isinstance(rec, dict) or rec.get("prev_sha256") != prev:
                    raise ValueError("cadena rota")
                if not all(nat(rec[k]) for k in ("epoch", "stop_seq") if k in rec):
                    raise ValueError("epoch o stop_seq no enteros")
                prev = sha256(raw)
                recs.append(rec)
        except (OSError, ValueError):
            raise Fail(2, f"JOURNAL_UNREADABLE: {self.journal_path}")
        self._journal_tail = prev
        return recs

    def git(self, *args, timeout=30):
        return run(["git", "-C", self.root, *args], timeout=timeout)

    def _origin_epoch(self):
        rc, _, _ = self.git("rev-parse", "--verify", "--quiet", "origin/main^{commit}")
        if rc:
            self.warnings.append("ORIGIN_MAIN_MISSING")
            return 0
        rc, ls, _ = self.git("ls-tree", "origin/main", "--", EPOCH_PATH)
        if rc:
            raise Fail(2, "ORIGIN_EPOCH_UNREADABLE: git ls-tree falló")
        if not ls.strip():
            return 0
        mode, typ = ls.split()[0], ls.split()[1]
        if mode != "100644" or typ != "blob":
            raise Fail(2, f"ORIGIN_EPOCH_UNREADABLE: {EPOCH_PATH} no es un fichero regular ({mode} {typ})")
        rc, content, _ = self.git("show", f"origin/main:{EPOCH_PATH}")
        if rc or not EPOCH_RE.fullmatch(content):
            raise Fail(2, f"ORIGIN_EPOCH_UNREADABLE: {EPOCH_PATH} en origin/main no es un entero de 1-9 cifras")
        return int(content)

    def _load_state(self):
        self.state, self.kind, self.raw_state = None, "OK", None
        if os.path.exists(self.state_path):
            try:
                with open(self.state_path, "rb") as f:
                    self.raw_state = f.read()
                st = json.loads(self.raw_state)
                if isinstance(st, dict) and isinstance(st.get("version"), int) and st["version"] > VERSION:
                    self.kind = "UNSUPPORTED_STATE_VERSION"
                elif self._valid_state(st):
                    self.state = st
                else:
                    self.kind = "UNREADABLE_STATE"
            except (OSError, ValueError):
                self.kind = "UNREADABLE_STATE"
        elif self.marker is not None or self.journal is not None:
            self.kind = "LOST_STATE"
        else:
            self.kind = "NEW"
            self.state = {"version": VERSION, "epoch": self.origin_epoch, "stop_seq": 0, "stops": {}}
        jl = self.journal or []
        mk = self.marker or {}
        local_epoch = [self.state["epoch"]] if self.kind == "OK" else []
        self.local_epoch = max([0, mk.get("epoch_hwm", 0), *local_epoch, *[r.get("epoch", 0) for r in jl]])
        local_seq = [self.state["stop_seq"]] if self.kind == "OK" else []
        self.epoch = max([0, self.origin_epoch, mk.get("epoch_hwm", 0), *local_epoch,
                          *[r.get("epoch", 0) for r in jl]])
        self.stop_seq = max([0, mk.get("stop_seq_hwm", 0), *local_seq, *[r.get("stop_seq", 0) for r in jl]])
        if self.kind in ("OK", "NEW"):
            self.stops = self.state["stops"]
        else:
            self.stops = {"global": {"mode": "REVOKED", "stop_seq": self.stop_seq + 1, "since": now(),
                                     "reason": self.kind, "actor": {"synthetic": True}, "synthetic": True}}

    @staticmethod
    def _valid_state(st):
        if not isinstance(st, dict) or set(st) != STATE_KEYS or not nat(st["version"]) or st["version"] != VERSION:
            return False
        if not (nat(st["epoch"]) and nat(st["stop_seq"]) and isinstance(st["stops"], dict)):
            return False
        for scope, e in st["stops"].items():
            if not valid_scope(scope) or not isinstance(e, dict) or set(e) != ENTRY_KEYS:
                return False
            if not (isinstance(e["mode"], str) and e["mode"] in STOP_MODES and nat(e["stop_seq"])
                    and isinstance(e["since"], str) and isinstance(e["reason"], str) and isinstance(e["actor"], dict)):
                return False
        return True

    # modos (R1)
    def mode_of(self, scopes):
        best, cause = "RUNNING", None
        for s in scopes:
            e = self.stops.get(s)
            if e and RANK[e["mode"]] > RANK[best]:
                best, cause = e["mode"], s
        return best, cause

    def executor_mode(self, name):
        return self.mode_of(["global", f"executor:{name}"])[0]

    # registro de ejecutores
    def executors(self):
        p = os.path.join(self.cdir, "executors.json")
        if not os.path.exists(p):
            return {}, sha256(b"")
        try:
            with open(p, "rb") as f:
                raw = f.read()
            reg = json.loads(raw)
            assert isinstance(reg, dict) and all(ID_RE.fullmatch(k) and isinstance(v, dict) for k, v in reg.items())
        except (OSError, ValueError, AssertionError):
            raise Fail(2, f"REGISTRY_UNREADABLE: {p}")
        return reg, sha256(raw)

    def remote_executors(self):
        rc, _, _ = self.git("rev-parse", "--verify", "--quiet", "origin/main^{commit}")
        if rc:
            return set()
        rc, ls, _ = self.git("ls-tree", "origin/main", "--", REMOTE_PATH)
        if rc or not ls.strip():
            return set()
        rc, content, _ = self.git("show", f"origin/main:{REMOTE_PATH}")
        try:
            data = json.loads(content)
            names = data.get("executors", []) if isinstance(data, dict) else data
            assert isinstance(names, list) and all(isinstance(n, str) and ID_RE.fullmatch(n) for n in names)
        except (ValueError, AssertionError):
            raise Fail(2, f"REMOTE_REGISTRY_UNREADABLE: {REMOTE_PATH} en origin/main")
        return set(names)

    # escritura
    def append(self, rec):
        try:
            reg, reg_sha = self.executors()
        except Fail:
            # Un registro ilegible no puede impedir dejar constancia de una parada (R1): se anota como tal.
            reg, reg_sha = {}, "REGISTRY_UNREADABLE"
        rec = {"ts": now(), **rec, "epoch": rec.get("epoch", self.epoch),
               "stop_seq": rec.get("stop_seq", self.stop_seq), "executors_sha256": reg_sha,
               "executors": sorted(reg), "prev_sha256": getattr(self, "_journal_tail", "genesis")
               if self.journal is not None else "genesis"}
        line = json.dumps(rec, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
        os.makedirs(self.cdir, exist_ok=True)
        if getattr(self, "_journal_cut", None) is not None:
            with open(self.journal_path, "rb") as f:
                f.seek(self._journal_cut)
                tail = f.read()
            atomic_write(f"{self.journal_path}.truncated-{sha256(tail)[:12]}", tail.decode(errors="replace"))
            os.truncate(self.journal_path, self._journal_cut)
            self._journal_cut = None
        with open(self.journal_path, "a") as f:
            f.write(line + "\n")
            f.flush()
            os.fsync(f.fileno())
        if self.journal is None:
            self.journal = []
        self.journal.append(rec)
        self._journal_tail = sha256(line.encode())

    def save_state(self):
        st = {"version": VERSION, "epoch": self.epoch, "stop_seq": self.stop_seq, "stops": self.stops}
        atomic_write(self.state_path, json.dumps(st, sort_keys=True, ensure_ascii=False, indent=1) + "\n")
        self.state, self.kind = st, "OK"

    def save_marker(self, consumed=None):
        m = dict(self.marker or {"version": VERSION, "consumed": []})
        m["control_dir"] = self.cdir
        for key in PINNED_PATHS:
            m.setdefault(key, self.paths[key])
        m["epoch_hwm"] = max(m.get("epoch_hwm", 0), self.epoch)
        m["stop_seq_hwm"] = max(m.get("stop_seq_hwm", 0), self.stop_seq)
        if consumed:
            m["consumed"] = list(m.get("consumed", [])) + [consumed]
        atomic_write(self.marker_path, json.dumps(m, sort_keys=True, indent=1) + "\n")
        self.marker = m

    def begin_write(self):
        """Prepara una orden que escribe: materializa el estado perdido o ilegible (R1)."""
        if self.kind == "UNSUPPORTED_STATE_VERSION":
            raise Fail(2, "UNSUPPORTED_STATE_VERSION: actualiza savia-control.py; el estado no se sobrescribe")
        os.makedirs(self.cdir, exist_ok=True)
        if self.kind in ("LOST_STATE", "UNREADABLE_STATE"):
            kind, entry = self.kind, self.stops["global"]
            entry.pop("synthetic", None)
            entry["actor"] = actor()
            if kind == "UNREADABLE_STATE" and os.path.exists(self.state_path):
                aside = f"{self.state_path}.unreadable-{sha256(self.raw_state or b'')[:12]}"
                os.replace(self.state_path, aside)
            self.stop_seq = entry["stop_seq"]
            self.save_state()
            self.append({"op": kind, "scope": "global", "mode": "REVOKED", "reason": kind, "actor": entry["actor"]})
            self.save_marker()
        elif self.journal is None and self.kind == "OK" and os.path.exists(self.state_path):
            self.append({"op": "JOURNAL_NEW", "state_sha256": sha256(self.raw_state or b"")})


def lock(ctx):
    os.makedirs(ctx.cdir, exist_ok=True)
    fd = os.open(os.path.join(ctx.cdir, ".lock"), os.O_CREAT | os.O_RDWR, 0o600)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


# ── adaptadores (R4; los concretos son F1) ──────────────────────────────────

def ack_timeout():
    """Segundos de espera del acuse. Un valor inválido no puede dejar la parada sin propagar: se avisa y se usa 10."""
    raw = os.environ.get("SAVIA_CONTROL_ACK_TIMEOUT_S", "10")
    try:
        t = float(raw)
        assert 0 < t < float("inf")
        return t
    except (ValueError, AssertionError):
        print(f"WARN ACK_TIMEOUT_INVALID: SAVIA_CONTROL_ACK_TIMEOUT_S={raw[:40]!r}; se usan 10 s", file=sys.stderr)
        return 10.0


def call_adapter(ctx, name, spec, args):
    """Invoca el adaptador con reintento único. Devuelve el dict de respuesta o None."""
    adapter = spec.get("adapter")
    timeout = ack_timeout()
    attempts = []
    for _ in range(2):
        if not isinstance(adapter, str) or not os.path.isabs(adapter) or not os.access(adapter, os.X_OK):
            attempts.append({"ok": False, "error": "ADAPTER_MISSING"})
            continue
        rc, so, se = run([adapter, *args], timeout=timeout)
        try:
            resp = json.loads(so) if rc == 0 else None
            if not isinstance(resp, dict) or resp.get("native_state") not in ("RUNNING", "STOPPED"):
                raise ValueError(f"rc={rc} {se.strip()[:120]}")
            attempts.append({"ok": True, "native_state": resp["native_state"]})
            return resp, attempts
        except ValueError as e:
            attempts.append({"ok": False, "error": str(e)[:200]})
    return None, attempts


def propagate(ctx, before, op, reason="", targets=None):
    """Llama a halt/resume de los ejecutores afectados y registra su acuse (R4).

    halt: los de `targets` (None = todos) que quedan en un modo parado. resume: los que
    pasan de un modo parado a RUNNING. Los remotos (origin/main) no se llaman.
    """
    reg, _ = ctx.executors()
    remote = ctx.remote_executors()
    lines = []
    for name, spec in sorted(reg.items()):
        if name in remote:
            continue
        mode = ctx.executor_mode(name)
        if op == "halt" and (mode == "RUNNING" or (targets is not None and name not in targets)):
            continue
        if op == "resume" and not (mode == "RUNNING" and before.get(name) != "RUNNING"):
            continue
        args = ["halt", str(ctx.epoch), mode, reason] if op == "halt" else ["resume", str(ctx.epoch)]
        resp, attempts = call_adapter(ctx, name, spec, args)
        ctx.append({"op": "ack", "executor": name, "call": op, "attempts": attempts, "ok": resp is not None})
        if resp is None:
            lines.append(f"SIN_ACUSE {name}")
            continue
        ack = {"executor": name, "epoch": ctx.epoch, "mode": mode, "native_state": resp["native_state"],
               "at": now(), "pending_manual": resp.get("pending_manual")}
        atomic_write(os.path.join(ctx.cdir, "acks", f"{name}.json"), json.dumps(ack, sort_keys=True) + "\n")
        if op == "resume" and resp["native_state"] == "STOPPED":
            lines.append(f"RESUME_INCOMPLETE {name}: {resp.get('pending_manual') or '(sin orden)'}")
    return lines


# ── órdenes de parada ───────────────────────────────────────────────────────

def check_reason(reason):
    if reason is None or not reason.strip() or len(reason.encode()) > 500:
        raise Fail(2, "REASON_INVALID: --reason obligatorio, no vacío y de 500 bytes como máximo")


def stop_order(scope, mode, reason, op):
    check_reason(reason)
    if not valid_scope(scope):
        raise Fail(2, f"SCOPE_INVALID: {scope}")
    ctx = Ctx()
    fd = lock(ctx)
    try:
        ctx = Ctx()
        ctx.begin_write()
        try:
            reg, _ = ctx.executors()
            reg_error = None
        except Fail as e:
            # La parada no depende de poder leer los adaptadores (como `check`, que no los consulta):
            # se persiste primero y el fallo de propagación se notifica después con exit 2.
            reg, reg_error = {}, e
        before = {n: ctx.executor_mode(n) for n in reg}
        if op == "revoke":
            ctx.epoch += 1
        ctx.stop_seq += 1
        who = actor()
        prev = ctx.stops.get(scope)
        new_mode = mode if not prev or RANK[mode] >= RANK[prev["mode"]] else prev["mode"]
        ctx.stops[scope] = {"mode": new_mode, "stop_seq": ctx.stop_seq, "since": now(), "reason": reason, "actor": who}
        ctx.save_state()
        ctx.append({"op": op, "scope": scope, "mode": new_mode, "reason": reason, "actor": who})
        ctx.save_marker()
        out(f"{op.upper()} {scope} {new_mode} epoch={ctx.epoch} stop_seq={ctx.stop_seq}")
        if op == "revoke" and ctx.epoch > ctx.origin_epoch:
            out(f"EPOCH_PENDING_PUBLISH: época local {ctx.epoch}, origin/main {ctx.origin_epoch}; "
                "publica con `savia-control.py publish-epoch`")
        if reg_error is not None:
            out(f"PROPAGATION_SKIPPED: {reg_error.msg}; la parada está registrada pero ningún adaptador recibió la orden")
            return reg_error.code
        if not scope.startswith(("principal:", "contract:")):
            targets = {scope.split(":", 1)[1]} if scope.startswith("executor:") else None
            for line in propagate(ctx, before, "halt", reason, targets):
                out(line)
    finally:
        os.close(fd)
    return 0


# ── check / epoch / status ──────────────────────────────────────────────────

def cmd_check(a):
    for v in (a.executor, a.principal, a.contract):
        if v is not None and not ID_RE.fullmatch(v):
            raise Fail(2, f"ID_INVALID: {v}")
    ctx = Ctx()
    scopes = ["global", f"executor:{a.executor}"]
    scopes += [f"principal:{a.principal}"] if a.principal else []
    scopes += [f"contract:{a.contract}"] if a.contract else []
    mode, cause = ctx.mode_of(scopes)
    if mode != "RUNNING":
        e = ctx.stops[cause]
        extra = f" {ctx.kind}" if ctx.kind not in ("OK", "NEW") else ""
        out(f"{mode} por {cause} (stop_seq={e['stop_seq']}): {e['reason']!r}{extra}")
        return 6
    if a.issued_epoch is not None:
        if a.issued_epoch < ctx.epoch:
            out(f"STALE_EPOCH: grant de la época {a.issued_epoch}, vigente {ctx.epoch}")
            return 8
        if a.issued_epoch > ctx.epoch:
            out(f"FORGED_EPOCH: grant de la época {a.issued_epoch}, vigente {ctx.epoch}")
            return 8
    out(f"RUNNING epoch={ctx.epoch}")
    return 0


def gh_api(ctx, path, paginate=False):
    """gh api. Con paginate, recorre todas las páginas de una lista (un elemento JSON por línea)."""
    cmd = ["gh", "api", path, "--paginate", "--jq", ".[]"] if paginate else ["gh", "api", path]
    rc, so, se = run(cmd, cwd=ctx.root, timeout=60 if paginate else 20)
    if rc:
        raise Fail(4, f"GH_API_FAILED: {path}: {se.strip()[:160]}")
    try:
        return [json.loads(x) for x in so.splitlines() if x.strip()] if paginate else json.loads(so)
    except ValueError:
        raise Fail(4, f"GH_API_FAILED: {path}: respuesta no JSON")


def main_rules(ctx):
    rules = gh_api(ctx, "repos/{owner}/{repo}/rules/branches/main")
    if not isinstance(rules, list):
        raise Fail(4, "GH_API_FAILED: reglas de main con formato inesperado")
    return rules


def epoch_warnings(ctx):
    w = list(ctx.warnings)
    try:
        rules = main_rules(ctx)
        checks = [c for r in rules if isinstance(r, dict) and r.get("type") == "required_status_checks"
                  for c in (r.get("parameters") or {}).get("required_status_checks", []) or []
                  if isinstance(c, dict) and c.get("context") == EPOCH_CHECK]
    except Fail:
        checks = []
    if not checks:
        w.append("EPOCH_CHECK_NOT_REQUIRED")
    elif not any(c.get("integration_id") == ACTIONS_APP_ID for c in checks):
        # Sin integration_id, cualquier app con permiso de checks puede publicar un verde con ese nombre. Fijar la app
        # de GitHub Actions lo reduce a workflows de Actions, pero NO impide que un workflow `on: pull_request` nuevo o
        # modificado de la propia PR publique un job con el mismo nombre: eso lo frena solo que tocar
        # .github/workflows/ sea tier 4 (fusión manual). Este aviso no es garantía de origen del check.
        w.append("EPOCH_CHECK_SOURCE_UNPINNED")
    return w


def cmd_epoch(a):
    ctx = Ctx()
    out(str(ctx.epoch))
    for w in epoch_warnings(ctx):
        print(f"WARN {w}", file=sys.stderr)
    print(f"origin/main (último fetch): {ctx.origin_epoch}", file=sys.stderr)
    return 0


def weak_resumes(ctx):
    weak = {}
    for r in ctx.journal or []:
        if r.get("op") == "resume" and r.get("via") == "terminal":
            weak[r["scope"]] = True
        elif r.get("op") in ("pause", "revoke", "quarantine", "LOST_STATE", "UNREADABLE_STATE"):
            weak.pop(r.get("scope"), None)
    return sorted(weak)


def cmd_status(a):
    ctx = Ctx()
    reg, reg_sha = ctx.executors()
    remote = ctx.remote_executors()
    rep = {"epoch": ctx.epoch, "origin_epoch": ctx.origin_epoch, "stop_seq": ctx.stop_seq,
           "warnings": epoch_warnings(ctx), "state": ctx.kind, "stops": [], "effect_scoped_stops": [],
           "executors": [], "propagation_incomplete": [], "resume_incomplete": [], "remote_unacked": [],
           "weak_resume": weak_resumes(ctx)}
    if ctx.kind not in ("OK", "NEW"):
        rep["warnings"].append(f"{ctx.kind} stop_seq={ctx.stops['global']['stop_seq']}")
    if ctx.kind == "OK" and ctx.journal is None and os.path.exists(ctx.state_path):
        rep["warnings"].append("JOURNAL_MISSING")
    last = next((r for r in reversed(ctx.journal or []) if "executors_sha256" in r and r.get("op") != "ack"), None)
    if last and last["executors_sha256"] != reg_sha:
        old = set(last.get("executors", []))
        rep["warnings"].append("REGISTRY_CHANGED +" + ",".join(sorted(set(reg) - old)) +
                               " -" + ",".join(sorted(old - set(reg))))
    for scope, e in sorted(ctx.stops.items()):
        item = {"scope": scope, **{k: e[k] for k in ("mode", "stop_seq", "reason", "actor")}}
        key = "effect_scoped_stops" if scope.startswith(("principal:", "contract:")) else "stops"
        rep[key].append(item)
    for name, spec in sorted(reg.items()):
        if name in remote:
            rep["remote_unacked"].append(name)
            continue
        mode = ctx.executor_mode(name)
        resp, _ = call_adapter(ctx, name, spec, ["status"])
        native = resp["native_state"] if resp else "UNKNOWN"
        ack = None
        try:
            with open(os.path.join(ctx.cdir, "acks", f"{name}.json")) as f:
                ack = json.load(f)
        except (OSError, ValueError):
            pass
        rep["executors"].append({"executor": name, "expected": mode, "native_state": native,
                                 "ack_epoch": (ack or {}).get("epoch")})
        if mode != "RUNNING":
            if not ack or ack.get("epoch") != ctx.epoch or ack.get("mode") != mode or native != "STOPPED":
                rep["propagation_incomplete"].append(name)
        elif native != "RUNNING":
            pm = (resp or {}).get("pending_manual") or (ack or {}).get("pending_manual") or "(adaptador sin respuesta)"
            rep["resume_incomplete"].append({"executor": name, "pending_manual": pm})
    code = 3 if rep["propagation_incomplete"] or rep["resume_incomplete"] else 0
    if a.json:
        out(json.dumps(rep, ensure_ascii=False, sort_keys=True))
        return code
    out(f"epoch: {rep['epoch']} (origin/main: {rep['origin_epoch']}) · stop_seq: {rep['stop_seq']}")
    for w in rep["warnings"]:
        out(f"WARN {w}")
    for s in rep["stops"]:
        act = s["actor"] or {}
        out(f"STOP {s['scope']} {s['mode']} stop_seq={s['stop_seq']} motivo={s['reason']!r} "
            f"actor=uid:{act.get('uid')} pid:{act.get('pid')} ancestros:{'>'.join(act.get('ancestors', []))}"
            f" declarado:{act.get('declared', '')!r}")
    for s in rep["effect_scoped_stops"]:
        out(f"EFFECT_SCOPED_STOPS {s['scope']} {s['mode']} stop_seq={s['stop_seq']} motivo={s['reason']!r}")
    for e in rep["executors"]:
        out(f"EXECUTOR {e['executor']} esperado={e['expected']} nativo={e['native_state']} acuse={e['ack_epoch']}")
    if rep["propagation_incomplete"]:
        out("PROPAGATION_INCOMPLETE " + " ".join(rep["propagation_incomplete"]))
    for r in rep["resume_incomplete"]:
        out(f"RESUME_INCOMPLETE {r['executor']}: {r['pending_manual']}")
    for n in rep["remote_unacked"]:
        out(f"REMOTE_UNACKED {n}: ejecutor remoto, no ha recibido la parada")
    for s in rep["weak_resume"]:
        out(f"WEAK_RESUME {s}: reanudado por vía débil (terminal)")
    return code


# ── reconcile (R5) ──────────────────────────────────────────────────────────

OWNER_KEYS = ("executor", "principal", "contract")
# Campos que describen un intento concreto: la evidencia de un intento (sonda, recibo, compensación) no vale para otro.
ATTEMPT_KEYS = ("state", "probe", "receipt", "compensation")


def ledger_records(ctx):
    """Ledger de efectos (SE-493). Interino en F0: JSONL; por effect_id se fusionan sus registros.

    - La atribución se acumula: un registro posterior no borra un dueño ya conocido (ni con null). Un valor de
      atribución malformado marca el efecto como sin atribución fiable, que cuenta en todos los ámbitos (fail-closed).
    - Estado, sonda, recibo y compensación salen solo de los registros del intento más alto: la sonda definitiva del
      intento 0 no prueba nada sobre el intento 1. Un registro sin `attempt` pertenece al intento vigente.
    - `irreversible` es pegajoso: basta un registro que lo diga.
    """
    p = ctx.paths["effect_ledger"]
    recs, owners, attempts, cur = {}, {}, {}, {}
    if os.path.exists(p):
        try:
            with open(p) as f:
                for line in f:
                    if not line.strip():
                        continue
                    r = json.loads(line)
                    if not isinstance(r, dict) or not isinstance(r.get("effect_id"), str):
                        raise ValueError
                    eid = r["effect_id"]
                    att = r.get("attempt", cur.get(eid, 0))
                    if not isinstance(att, int) or isinstance(att, bool) or att < 0:
                        raise ValueError
                    cur[eid] = max(cur.get(eid, att), att)
                    per = attempts.setdefault(eid, {})
                    per[att] = {**per.get(att, {}), **{k: r[k] for k in ATTEMPT_KEYS if k in r}}
                    own = owners.setdefault(eid, {"_malformed": False})
                    for k in OWNER_KEYS:
                        if k in r:
                            if isinstance(r[k], str) and r[k]:
                                own.setdefault(k, set()).add(r[k])
                            elif r[k] is not None:
                                own["_malformed"] = True
                    sticky = bool(recs.get(eid, {}).get("irreversible")) or r.get("irreversible") is True
                    recs[eid] = {**recs.get(eid, {}), **r, "irreversible": sticky}
        except (OSError, ValueError):
            raise Fail(2, f"LEDGER_UNREADABLE: {p}")
    for eid, rec in recs.items():
        for k in ATTEMPT_KEYS:
            rec.pop(k, None)
        rec.update(attempts[eid][cur[eid]])
        rec["attempt"] = cur[eid]
        rec["_owners"] = owners[eid]
    return recs


def known_indeterminate(ctx):
    """Efectos que algún reconcile dejó INDETERMINATE y que nada ha descargado después (diario encadenado).

    Los descarga un reconcile posterior que los clasifique como resueltos (en cualquier ámbito: la clase de un efecto
    no depende del ámbito desde el que se mira) o un resume que los acepte expresamente. Renovar una parada (nuevo
    stop_seq) o levantar otra no aporta evidencia sobre el efecto y no lo descarga.

    La aceptación es por ámbito: aceptar e1 al reanudar executor:a no lo descarga de principal:p si ese ámbito también
    lo dejó incierto. Se lleva el par (efecto, ámbito) y el efecto cuenta mientras le quede algún ámbito.
    """
    pending = {}
    for r in ctx.journal or []:
        if r.get("op") == "reconcile":
            for c in r.get("scopes", []):
                if not isinstance(c, dict):
                    continue
                for x in c.get("resolved", []):
                    if isinstance(x, str):
                        pending.pop(x, None)
            for c in r.get("scopes", []):
                if isinstance(c, dict):
                    sc = c.get("scope") if isinstance(c.get("scope"), str) else "?"
                    for x in c.get("indeterminate", []):
                        if isinstance(x, str):
                            pending.setdefault(x, set()).add(sc)
        elif r.get("op") == "resume" and isinstance(r.get("scope"), str):
            for a in r.get("accepted", []):
                if isinstance(a, dict) and a.get("effect_id") in pending:
                    pending[a["effect_id"]].discard(r["scope"])
                    if not pending[a["effect_id"]]:
                        del pending[a["effect_id"]]
    return set(pending)


def covers(scope, rec):
    if scope == "global":
        return True
    kind, _, ident = scope.partition(":")
    own = rec.get("_owners")
    if own is None:  # registro no pasado por ledger_records
        own = {k: {rec[k]} for k in OWNER_KEYS if isinstance(rec.get(k), str) and rec[k]}
    if own.get("_malformed") or not any(own.get(k) for k in OWNER_KEYS):
        return True  # sin atribución fiable no se puede descartar de ningún ámbito: fail-closed
    return ident in own.get(kind, ())


def abandon(effect_id):
    tool = os.path.join(SCRIPT_DIR, "effect-ledger.py")
    if not os.path.exists(tool):
        return False
    rc, _, _ = run([sys.executable, "-I", tool, "abandon", effect_id, "--reason", "control-reconcile"])
    return rc == 0


def classify(ctx, rec):
    st, receipt = rec.get("state"), rec.get("receipt")
    comp = rec.get("compensation") or {}
    probe = rec.get("probe") or {}
    if st == "SUCCEEDED" and receipt and isinstance(comp, dict) and comp.get("state") == "SUCCEEDED":
        return "COMPENSATED"
    if st == "SUCCEEDED" and receipt:
        return "CONFIRMED"
    if st == "FAILED" and isinstance(probe, dict) and probe.get("result") == "ABSENT" and probe.get("definitive") is True:
        return "REJECTED"
    if st == "ABANDONED":
        return "REJECTED"
    if st == "PREPARED":
        if not abandon(rec["effect_id"]):
            return "INDETERMINATE"
        fresh = Ctx()  # ¿sigue parado el ámbito tras la transición?
        mode, _ = fresh.mode_of([s for s in fresh.stops if covers(s, rec)])
        return "REJECTED" if mode != "RUNNING" else "INDETERMINATE"
    return "INDETERMINATE"


def cmd_reconcile(a):
    if a.scope and not valid_scope(a.scope):
        raise Fail(2, f"SCOPE_INVALID: {a.scope}")
    ctx = Ctx()
    fd = lock(ctx)
    try:
        ctx = Ctx()
        ctx.begin_write()
        if ctx.kind == "NEW":
            ctx.save_state()  # sin esto la marca y el diario existirían sin estado y el siguiente check daría LOST_STATE
        effects = ledger_records(ctx)
        scopes = [a.scope] if a.scope else sorted(ctx.stops)
        scopes = [s for s in scopes if s in ctx.stops]
        gone = sorted(known_indeterminate(ctx) - set(effects))
        if gone:
            # Un ledger ausente o sin efectos ya reconocidos como inciertos no prueba que estén resueltos. Sin su
            # registro no se sabe a qué ámbitos pertenecían, así que bloquea el reconcile de cualquier ámbito.
            raise Fail(2, "LEDGER_UNREADABLE: faltan en el ledger efectos INDETERMINATE de un reconcile "
                          f"anterior ({', '.join(gone[:5])}); no se da por vacío. Restaura el ledger o registra "
                          "en él su resolución")
        report, covered, any_indet = [], [], False
        for eid, rec in sorted(effects.items()):
            hit = [s for s in scopes if covers(s, rec)]
            if not hit:
                continue
            cls = classify(ctx, rec)
            any_indet |= cls == "INDETERMINATE"
            report.append({"effect_id": eid, "class": cls, "scopes": hit, "ledger_state": rec.get("state"),
                           "irreversible": bool(rec.get("irreversible"))})
        for s in scopes:
            indet = sorted(r["effect_id"] for r in report if s in r["scopes"] and r["class"] == "INDETERMINATE")
            done = sorted(r["effect_id"] for r in report if s in r["scopes"] and r["class"] != "INDETERMINATE")
            covered.append({"scope": s, "stop_seq": ctx.stops[s]["stop_seq"], "indeterminate": indet,
                            "resolved": done})
        path = os.path.join(ctx.cdir, "reports", f"reconcile-{ctx.stop_seq}-{int(time.time() * 1000)}.json")
        atomic_write(path, json.dumps({"at": now(), "scopes": covered, "effects": report}, indent=1) + "\n")
        ctx.append({"op": "reconcile", "scopes": covered, "report": os.path.basename(path), "actor": actor()})
        ctx.save_marker()
        for r in report:
            note = " (irreversible: no se puede deshacer)" if r["irreversible"] else ""
            out(f"{r['class']} {r['effect_id']} [{','.join(r['scopes'])}]{note}")
        out(f"RECONCILE {' '.join(c['scope'] + '@' + str(c['stop_seq']) for c in covered) or '(sin ámbitos parados)'}"
            f" informe={path}")
    finally:
        os.close(fd)
    return 5 if any_indet else 0


# ── resume (R6) ─────────────────────────────────────────────────────────────

def scope_hash(scope):
    return sha256(scope)[:16]


def forbidden(chain):
    for p in chain:
        args = p.get("cmdline", [])
        if p["comm"] in FORBIDDEN_ANCESTORS or p["comm"].startswith("overnight-sprin"):
            return p
        if any("overnight-sprint-loop" in x for x in args):
            return p
        if p["comm"] == "node" and any(("claude" in x or "opencode" in x) for x in args):
            return p
    return None


def verify_terminal(scope, entry):
    if not (sys.stdin.isatty() and sys.stdout.isatty()):
        raise Fail(4, "NO_APPROVAL: sin terminal interactiva ni --via-pr; solo la operadora reanuda")
    chain = ancestors(full=True)
    if chain is None:
        raise Fail(4, "NO_APPROVAL: no se puede leer la cadena de ancestros")
    bad = forbidden(chain)
    if bad:
        raise Fail(4, f"NO_APPROVAL: un ancestro es un ejecutor conocido ({bad['comm']}, pid {bad['pid']})")
    try:
        print(f"Reanudar {scope} (stop_seq {entry['stop_seq']}). Teclea el ámbito: ", end="", flush=True)
        typed_scope = input().strip()
        print("Teclea el stop_seq: ", end="", flush=True)
        typed_seq = input().strip()
    except EOFError:
        raise Fail(4, "NO_APPROVAL: entrada interrumpida")
    if typed_scope != scope or typed_seq != str(entry["stop_seq"]):
        raise Fail(4, "NO_APPROVAL: ámbito o stop_seq tecleados no coinciden")
    return chain


def blob_consumed(ctx, blob):
    if not isinstance(blob, str) or not re.fullmatch(r"[0-9a-f]{40,64}", blob):
        raise Fail(4, "APPROVAL_UNTRACEABLE: no se pudo resolver el blob de la aprobación")
    return any(r.get("approval_blob") == blob for r in ctx.journal or []) or blob in (ctx.marker or {}).get("consumed", [])


def origin_tier(ctx, files):
    rc, src, _ = ctx.git("show", "origin/main:scripts/risk-tier.py")
    if rc:
        raise Fail(4, "TIER_UNVERIFIABLE: no hay scripts/risk-tier.py en origin/main")
    with tempfile.TemporaryDirectory() as td:
        p = os.path.join(td, "risk-tier.py")
        with open(p, "w") as f:
            f.write(src)
        rc, so, _ = run([sys.executable, "-I", p, "--diff", " ".join(files), "--json"], cwd=td)
    try:
        return int(json.loads(so)["tier"])
    except (ValueError, KeyError, TypeError):
        raise Fail(4, "TIER_UNVERIFIABLE: risk-tier.py de origin/main no respondió")


def merge_sprint_merged(ctx, pr):
    p = os.path.join(ctx.paths["merge_sprint_home"], "ledger.jsonl")
    if not os.path.exists(p):
        return False
    try:
        with open(p) as f:
            return any(d.get("event") == "MERGED" and str(d.get("pr")) == str(pr) for d in map(json.loads, filter(str.strip, f)))
    except (OSError, ValueError, AttributeError):
        raise Fail(4, "MERGE_SPRINT_LEDGER_UNREADABLE")


def verify_pr(ctx, scope, entry):
    """Aprobación por fusión de PR (R6.1). Devuelve (blob, accept). Cualquier fallo: exit 4."""
    path = f"{RESUME_DIR}/{ctx.epoch}-{entry['stop_seq']}-{scope_hash(scope)}.json"
    rc, ls, _ = ctx.git("ls-tree", "origin/main", "--", path)
    if rc or not ls.strip() or ls.split()[:2] != ["100644", "blob"]:
        raise Fail(4, f"APPROVAL_MISSING: {path} no está en origin/main")
    rc, content, _ = ctx.git("show", f"origin/main:{path}")
    try:
        ap = json.loads(content)
        assert isinstance(ap, dict) and set(ap) == {"epoch", "stop_seq", "scope", "reason", "accept"}
        assert isinstance(ap["scope"], str) and valid_scope(ap["scope"]) and ap["scope"] == scope
        assert scope_hash(ap["scope"]) == path.rsplit("-", 1)[1][:-5]
        assert nat(ap["epoch"]) and nat(ap["stop_seq"])  # True o 1.0 no valen por 1
        assert ap["epoch"] == ctx.epoch and ap["stop_seq"] == entry["stop_seq"]
        assert isinstance(ap["accept"], list) and all(isinstance(x, str) for x in ap["accept"])
    except (ValueError, AssertionError, TypeError):
        raise Fail(4, f"APPROVAL_INVALID: {path} no casa con época, ámbito o stop_seq vigentes")
    _, blob, _ = ctx.git("rev-parse", f"origin/main:{path}")
    blob = blob.strip()
    if blob_consumed(ctx, blob):
        raise Fail(4, f"APPROVAL_CONSUMED: el blob {blob[:12]} ya se usó")
    rc, op, _ = ctx.git("show", f"origin/main:{OPERATOR_PATH}")
    try:
        login = json.loads(op)["login"] if rc == 0 else None
        assert isinstance(login, str) and LOGIN_RE.fullmatch(login)
    except (ValueError, KeyError, TypeError, AssertionError):
        raise Fail(4, f"OPERATOR_UNKNOWN: {OPERATOR_PATH} ausente o inválido en origin/main")
    if not any(isinstance(r, dict) and r.get("type") == "pull_request" for r in main_rules(ctx)):
        raise Fail(4, "RULE_INACTIVE: main no exige PR")
    # La última PR que tocó la aprobación (la que la añadió o una posterior que la cambió) es la que se verifica.
    rc, commit, _ = ctx.git("log", "origin/main", "--format=%H", "-1", "--", path)
    if rc or not commit.strip():
        raise Fail(4, "APPROVAL_UNTRACEABLE: no se encuentra el commit que fijó la aprobación")
    pulls = gh_api(ctx, f"repos/{{owner}}/{{repo}}/commits/{commit.strip()}/pulls", paginate=True)
    merged = [p for p in pulls if isinstance(p, dict) and p.get("merged_at")]
    if not merged:
        raise Fail(4, "APPROVAL_UNTRACEABLE: la aprobación no llegó por una PR fusionada")
    if len(merged) > 1:
        raise Fail(4, "APPROVAL_UNTRACEABLE: el commit de la aprobación figura en varias PR fusionadas: "
                   + ",".join(str(p.get("number")) for p in merged))
    n = merged[0].get("number")
    pr = gh_api(ctx, f"repos/{{owner}}/{{repo}}/pulls/{n}")
    if not isinstance(pr, dict) or ((pr.get("merged_by") or {}).get("login")) != login:
        raise Fail(4, f"MERGED_BY_OTHER: la PR #{n} no la fusionó {login}")
    files = gh_api(ctx, f"repos/{{owner}}/{{repo}}/pulls/{n}/files", paginate=True)
    names = [f.get("filename") for f in files if isinstance(f, dict)]
    # Un renombrado desde un ámbito protegido: el nombre antiguo también cuenta para el tier.
    names += [f["previous_filename"] for f in files if isinstance(f, dict) and f.get("previous_filename")]
    if not names or not all(isinstance(x, str) for x in names):
        raise Fail(4, f"APPROVAL_UNTRACEABLE: sin ficheros para la PR #{n}")
    if any(re.search(r"\s", x) for x in names):
        # risk-tier.py --diff separa por espacios: un nombre con espacios no se puede clasificar fiable
        raise Fail(4, f"TIER_UNVERIFIABLE: la PR #{n} tiene ficheros con espacios en el nombre")
    if origin_tier(ctx, names) != 4:
        raise Fail(4, f"TIER_NOT_4: la PR #{n} no sale tier 4 con el risk-tier.py de origin/main")
    if merge_sprint_merged(ctx, n):
        raise Fail(4, f"MERGED_BY_SPRINT: la PR #{n} figura MERGED en el ledger del merge-sprint")
    return blob, ap["accept"], n


def last_reconcile(ctx, scope, seq):
    for r in reversed(ctx.journal or []):
        if r.get("op") == "reconcile":
            for c in r.get("scopes", []):
                if c.get("scope") == scope and c.get("stop_seq") == seq:
                    return set(c.get("indeterminate", []))
    return None


def cmd_resume(a):
    scope = a.scope or "global"
    if not valid_scope(scope):
        raise Fail(2, f"SCOPE_INVALID: {scope}")

    def load():
        c = Ctx()
        if c.kind == "UNSUPPORTED_STATE_VERSION":
            raise Fail(2, "UNSUPPORTED_STATE_VERSION: actualiza savia-control.py")
        if scope != "global" and "global" in c.stops:
            raise Fail(9, f"STILL_COVERED_BY global: primero se levanta global ({scope} sigue parado)")
        return c

    ctx = load()
    fd = lock(ctx)
    try:
        ctx = load()
        if scope not in ctx.stops:
            out(f"NOT_STOPPED {scope}: nada que reanudar")
            return 0
        chain, blob, pr = None, None, None
        if a.via_pr:
            rc, _, se = ctx.git("fetch", "--quiet", "origin", "main", timeout=60)
            if rc:
                raise Fail(4, f"FETCH_FAILED: {se.strip()[:160]}")
            ctx = load()
            if scope not in ctx.stops:
                out(f"NOT_STOPPED {scope}: nada que reanudar")
                return 0
            blob, accept, pr = verify_pr(ctx, scope, ctx.stops[scope])
        else:
            chain = verify_terminal(scope, ctx.stops[scope])
        entry = ctx.stops[scope]
        indet = last_reconcile(ctx, scope, entry["stop_seq"])
        if indet is None:
            raise Fail(5, f"RECONCILE_REQUIRED: ningún reconcile cubrió {scope} con stop_seq {entry['stop_seq']}")
        if chain is not None:
            accept = []
            for eid in sorted(indet):
                print(f"Efecto INDETERMINATE {eid}. Teclea «acepto {eid}»: ", end="", flush=True)
                try:
                    if input().strip() == f"acepto {eid}":
                        accept.append(eid)
                except EOFError:
                    break
        if set(accept) != indet:
            raise Fail(5, "ACCEPT_MISMATCH: faltan " + ",".join(sorted(indet - set(accept))) +
                       " · sobran " + ",".join(sorted(set(accept) - indet)))
        reg, _ = ctx.executors()
        before = {n: ctx.executor_mode(n) for n in reg}
        del ctx.stops[scope]
        ctx.save_state()
        rec = {"op": "resume", "scope": scope, "entry_stop_seq": entry["stop_seq"], "actor": actor(),
               "via": "pr" if a.via_pr else "terminal",
               "accepted": [{"effect_id": e, "stop_seq": entry["stop_seq"],
                             "channel": "pr" if a.via_pr else "terminal", "approval_blob": blob} for e in sorted(accept)]}
        if a.via_pr:
            rec.update({"approval_blob": blob, "pr": pr})
        else:
            rec["ancestors"] = chain
        ctx.append(rec)
        ctx.save_marker(consumed=blob)
        out(f"RESUME {scope} epoch={ctx.epoch} via={rec['via']}")
        if not a.via_pr:
            out(f"WEAK_RESUME {scope}: reanudado por vía débil (terminal)")
        for line in propagate(ctx, before, "resume"):
            out(line)
    finally:
        os.close(fd)
    return 0


# ── publish-epoch (R2) ──────────────────────────────────────────────────────

def build_epoch_commit(ctx, n, msg):
    """Commit sobre origin/main que solo cambia EPOCH_PATH a n, con un índice temporal (no toca el árbol)."""
    with tempfile.TemporaryDirectory() as td:
        env = dict(os.environ, GIT_INDEX_FILE=os.path.join(td, "index"))
        steps = [["read-tree", "origin/main"]]
        for st in steps:
            if subprocess.run(["git", "-C", ctx.root, *st], env=env, capture_output=True).returncode:
                raise Fail(2, "PUBLISH_FAILED: read-tree")
        blob = subprocess.run(["git", "-C", ctx.root, "hash-object", "-w", "--stdin"], input=f"{n}\n",
                              text=True, capture_output=True).stdout.strip()
        r1 = subprocess.run(["git", "-C", ctx.root, "update-index", "--add", "--cacheinfo",
                             f"100644,{blob},{EPOCH_PATH}"], env=env, capture_output=True)
        tree = subprocess.run(["git", "-C", ctx.root, "write-tree"], env=env, capture_output=True, text=True)
        if not blob or r1.returncode or tree.returncode:
            raise Fail(2, "PUBLISH_FAILED: no se pudo construir el árbol")
        rc, commit, se = ctx.git("commit-tree", tree.stdout.strip(), "-p", "origin/main", "-m", msg)
        if rc:
            raise Fail(2, f"PUBLISH_FAILED: commit-tree: {se.strip()[:160]}")
    return commit.strip()


def reusable_epoch_branch(ctx, branch, n):
    """True si origin ya tiene la rama y solo sube EPOCH_PATH a n. Si existe con otro contenido: exit 2."""
    rc, ls, se = ctx.git("ls-remote", "--heads", "origin", f"refs/heads/{branch}", timeout=60)
    if rc:
        raise Fail(2, f"PUBLISH_FAILED: ls-remote: {se.strip()[:160]}")
    if not ls.strip():
        return False
    rc, _, se = ctx.git("fetch", "--quiet", "origin", f"+refs/heads/{branch}:refs/savia-control/{branch}", timeout=60)
    ref = f"refs/savia-control/{branch}"
    rc2, names, _ = ctx.git("diff", "--name-only", f"origin/main...{ref}")
    rc3, content, _ = ctx.git("show", f"{ref}:{EPOCH_PATH}")
    if rc or rc2 or rc3 or names.split() != [EPOCH_PATH] or content != f"{n}\n":
        raise Fail(2, f"BRANCH_EXISTS: {branch} ya existe en origin con otro contenido; revísala o bórrala a mano")
    return True


def cmd_publish_epoch(a):
    ctx = Ctx()
    rc, _, se = ctx.git("fetch", "--quiet", "origin", "main", timeout=60)
    if rc:
        raise Fail(2, f"FETCH_FAILED: {se.strip()[:160]}")
    ctx = Ctx()
    if ctx.local_epoch <= ctx.origin_epoch:
        out(f"NOTHING_TO_PUBLISH: época local {ctx.local_epoch}, origin/main {ctx.origin_epoch}")
        return 0
    n = ctx.origin_epoch + 1
    branch = f"agent/control-epoch-{n}"
    rc, so, se = run(["gh", "pr", "list", "--state", "open", "--json", "number,headRefName,url,isCrossRepository",
                      "--limit", "200"],
                     cwd=ctx.root)
    try:
        prs = json.loads(so) if rc == 0 else None
        assert isinstance(prs, list)
    except (ValueError, AssertionError):
        raise Fail(2, f"GH_FAILED: gh pr list: {se.strip()[:160]}")
    for p in prs:
        if not isinstance(p, dict) or p.get("isCrossRepository") is not False:
            continue  # una PR desde un fork (o sin el dato) no es nuestra: ni se cierra ni cuenta como publicada
        head = str(p.get("headRefName", ""))
        m = re.match(r"^agent/control-epoch-([0-9]{1,9})$", head)
        if m and int(m.group(1)) <= ctx.origin_epoch:
            run(["gh", "pr", "close", str(p.get("number")), "--comment",
                 f"SE-498: origin/main ya está en {ctx.origin_epoch}"], cwd=ctx.root)
        elif head == branch:
            out(f"ALREADY_OPEN: {p.get('url') or p.get('number')} publica la época {n}")
            return 0
    msg = f"chore(control): REVOCATION_EPOCH a {n} (SE-498)"
    if reusable_epoch_branch(ctx, branch, n):
        # un intento anterior empujó la rama pero no abrió la PR (gh pr create falló): se reutiliza sin forzar
        out(f"REUSE_BRANCH: {branch} ya está en origin con la época {n}")
    else:
        commit = build_epoch_commit(ctx, n, msg)
        rc, _, se = ctx.git("push", "--quiet", "origin", f"{commit}:refs/heads/{branch}", timeout=120)
        if rc:
            raise Fail(2, f"PUBLISH_FAILED: push: {se.strip()[:160]}")
    body = (f"Sube `{EPOCH_PATH}` de {ctx.origin_epoch} a {n} tras un `revoke` local (época local {ctx.local_epoch}).\n\n"
            "Tier 4 (`config/control/**`): la fusiona a mano la operadora; el merge-sprint no la fusiona.\n")
    rc, so, se = run(["gh", "pr", "create", "--draft", "--base", "main", "--head", branch, "--title", msg,
                      "--body", body], cwd=ctx.root)
    if rc:
        raise Fail(2, f"GH_FAILED: gh pr create: {se.strip()[:160]}")
    out(f"PUBLISHED {n}: {so.strip()}")
    return 0


# ── entrada ─────────────────────────────────────────────────────────────────

def parser():
    p = argparse.ArgumentParser(prog="savia-control.py", description="Plano de control local (SE-498)")
    sub = p.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("check")
    c.add_argument("--executor", required=True)
    c.add_argument("--principal")
    c.add_argument("--contract")
    c.add_argument("--issued-epoch", type=int)
    s = sub.add_parser("status")
    s.add_argument("--json", action="store_true")
    sub.add_parser("epoch")
    pa = sub.add_parser("pause")
    pa.add_argument("--scope", default="global")
    pa.add_argument("--reason")
    rv = sub.add_parser("revoke")
    rv.add_argument("--reason")
    q = sub.add_parser("quarantine")
    q.add_argument("executor")
    q.add_argument("--reason")
    rc = sub.add_parser("reconcile")
    rc.add_argument("--scope")
    rs = sub.add_parser("resume")
    rs.add_argument("--scope")
    rs.add_argument("--via-pr", action="store_true")
    sub.add_parser("publish-epoch", description=(
        "Prepara la rama agent/control-epoch-<N> y abre la PR. Sus git se ejecutan sin GIT_CONFIG_GLOBAL ni "
        "GIT_CONFIG_SYSTEM (se descartan al arrancar): identidad, credential helper o safe.directory deben estar en "
        "~/.gitconfig o en el config del repo, no en un fichero apuntado por esas variables."))
    return p


def main(argv):
    a = parser().parse_args(argv)
    try:
        if a.cmd == "check":
            return cmd_check(a)
        if a.cmd == "status":
            return cmd_status(a)
        if a.cmd == "epoch":
            return cmd_epoch(a)
        if a.cmd == "pause":
            return stop_order(a.scope, "PAUSED", a.reason, "pause")
        if a.cmd == "revoke":
            return stop_order("global", "REVOKED", a.reason, "revoke")
        if a.cmd == "quarantine":
            if not ID_RE.fullmatch(a.executor):
                raise Fail(2, f"ID_INVALID: {a.executor}")
            return stop_order(f"executor:{a.executor}", "QUARANTINED", a.reason, "quarantine")
        if a.cmd == "reconcile":
            return cmd_reconcile(a)
        if a.cmd == "resume":
            return cmd_resume(a)
        return cmd_publish_epoch(a)
    except Fail as e:
        print(e.msg, file=sys.stderr)
        return e.code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
