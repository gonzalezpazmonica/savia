#!/usr/bin/env python3
"""effect-ledger.py — SE-493 S1: Effect Ledger con reconciliación de efectos ambiguos.

Un único libro local (SQLite, write-ahead) por instalación. Ningún estado ambiguo
devuelve «adelante». Contrato completo: docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md

Órdenes (S1):
  prepare <op> --repo R --number N --head SHA --method M --holder-pid PID [--run-id X]
      0 PROCEED <eid> <token> | 3 ALREADY_EXECUTED | 4 NEEDS_REVIEW | 5 CONFLICT | 6 IN_FLIGHT | 2 error
  dispatch <eid> --claim T              sonda previa (3c) + CAS PREPARED→DISPATCHED (0 | 4 | 6 | 2)
  complete <eid> --claim T --response J SUCCEEDED con attribution response
      (0 | 6 sin evidencia, con rechazo anotado o si la respuesta contradice head/actor | 2)
  reject   <eid> --claim T --response X anota el rechazo (6 | 2)
  fail     <eid> --claim T --reason X   solo desde PREPARED (0 | 2)
  reconcile <key> [--op OP]             exits de la Regla 3d (3 | 7 | 4 | 6 | 0 | 2)
  resolve <eid> --by-probe [--outcome succeeded|failed]   (0 | 4 | 2); --manual llega en S2
  status <key> [--op OP] | status --open   (sin claim_token; claim_held true|false)
  verify-receipt <eid>                  0 VERIFIED | 1 FAIL | 4 UNVERIFIED | 2 error

Ledger: $HOME/.savia/effects/ledger.db. SAVIA_EFFECT_LEDGER solo con SAVIA_EFFECT_TEST=1 (7b).
Ganchos de prueba (SAVIA_EFFECT_NOW, SAVIA_EFFECT_FAULT, SAVIA_EFFECT_REGISTRY, SAVIA_EFFECT_PROC,
SAVIA_EFFECT_BUSY_MS) solo con SAVIA_EFFECT_TEST=1 y ledger bajo ${TMPDIR:-/tmp} (distinto de /)
y distinto del de por defecto tras realpath y por inodo (Regla 7). Ledger, WAL y lock en 0600.
"""
import fcntl
import hashlib
import json
import os
import re
import secrets
import signal
import sqlite3
import subprocess
import sys
import time
import uuid

EXIT_OK, EXIT_FAIL, EXIT_ERR, EXIT_DONE, EXIT_REVIEW, EXIT_CONFLICT, EXIT_INFLIGHT, EXIT_ALREADY = 0, 1, 2, 3, 4, 5, 6, 7
SCHEMA_VERSION = "1"
EFFECT_COLS = (
    "effect_id", "op", "idempotency_key", "attempt", "state", "args", "args_digest",
    "effect_class", "install_id", "actor", "actor_remote", "run_id", "claim_token",
    "lease_until", "holder_pid", "holder_start", "review_origin", "dispatch_rejected",
    "reject_response", "failure", "observation", "receipt", "resolution",
    "created_at", "updated_at", "dispatched_at",
)
SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS effects (
  effect_id TEXT PRIMARY KEY, op TEXT NOT NULL, idempotency_key TEXT NOT NULL,
  attempt INTEGER NOT NULL, state TEXT NOT NULL, args TEXT NOT NULL, args_digest TEXT,
  effect_class TEXT NOT NULL, install_id TEXT NOT NULL, actor TEXT, actor_remote TEXT,
  run_id TEXT, claim_token TEXT, lease_until INTEGER, holder_pid INTEGER, holder_start TEXT,
  review_origin TEXT, dispatch_rejected INTEGER NOT NULL DEFAULT 0, reject_response TEXT,
  failure TEXT, observation TEXT, receipt TEXT, resolution TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, dispatched_at INTEGER,
  UNIQUE (op, idempotency_key, attempt));
CREATE TABLE IF NOT EXISTS receipts (
  seq INTEGER PRIMARY KEY AUTOINCREMENT, effect_id TEXT NOT NULL UNIQUE,
  body TEXT NOT NULL, prev_hash TEXT NOT NULL, hash TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS events (
  seq INTEGER PRIMARY KEY AUTOINCREMENT, effect_id TEXT, ts INTEGER NOT NULL,
  event TEXT NOT NULL, detail TEXT);
"""
GENESIS = "0" * 64


class Fail(Exception):
    """Salida controlada con código y mensaje."""

    def __init__(self, code, msg=""):
        super().__init__(msg)
        self.code, self.msg = code, msg


def warn(msg):
    print(f"effect-ledger: {msg}", file=sys.stderr)


def canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# ── Entorno: ledger, ganchos de prueba (Reglas 7 y 7b) ─────────────────────

def same_inode(a, b):
    """True si a y b son el mismo fichero (enlace duro incluido)."""
    try:
        sa, sb = os.stat(a), os.stat(b)
    except OSError:
        return False
    return (sa.st_dev, sa.st_ino) == (sb.st_dev, sb.st_ino)


class Env:
    def __init__(self):
        home = os.environ.get("HOME", "")
        if not home:
            raise Fail(EXIT_ERR, "sin HOME: no se puede resolver el ledger")
        self.default = os.path.join(home, ".savia", "effects", "ledger.db")
        override = os.environ.get("SAVIA_EFFECT_LEDGER", "")
        self.test = os.environ.get("SAVIA_EFFECT_TEST") == "1"
        if override and not self.test:
            warn("SAVIA_EFFECT_LEDGER ignorado: solo vale con SAVIA_EFFECT_TEST=1 (Regla 7b)")
            override = ""
        self.path = override or self.default
        tmp = os.path.realpath(os.environ.get("TMPDIR") or "/tmp")
        real = os.path.realpath(self.path)
        self.hooks = bool(
            self.test and override and tmp != os.sep
            and os.path.commonpath([real, tmp]) == tmp
            and real != os.path.realpath(self.default)
            and not same_inode(real, self.default))
        hook_vars = [v for v in ("SAVIA_EFFECT_NOW", "SAVIA_EFFECT_FAULT", "SAVIA_EFFECT_REGISTRY",
                                 "SAVIA_EFFECT_PROC", "SAVIA_EFFECT_BUSY_MS") if os.environ.get(v)]
        if hook_vars and not self.hooks:
            warn("ganchos de prueba ignorados (" + ",".join(hook_vars) + "): exigen SAVIA_EFFECT_TEST=1 "
                 "y un ledger bajo ${TMPDIR:-/tmp} distinto del de por defecto (Regla 7)")

    def hook(self, name):
        return os.environ.get(name, "") if self.hooks else ""

    def now(self):
        v = self.hook("SAVIA_EFFECT_NOW")
        if v:
            if not re.fullmatch(r"[0-9]{1,12}", v):
                raise Fail(EXIT_ERR, "SAVIA_EFFECT_NOW inválido")
            return int(v)
        return int(time.time())

    def fault(self, point):
        if self.hook("SAVIA_EFFECT_FAULT") == point:
            os.kill(os.getpid(), signal.SIGKILL)

    def proc_root(self):
        return self.hook("SAVIA_EFFECT_PROC") or "/proc"


# ── Registro de operaciones ────────────────────────────────────────────────

PROBES = {"gh_pr_merge"}
VALIDATORS = ("repo", "pr_number", "sha40")


def load_registry(env):
    path = env.hook("SAVIA_EFFECT_REGISTRY") or os.path.join(os.path.dirname(os.path.abspath(__file__)), "effect-ops.json")
    try:
        with open(path, encoding="utf-8") as fh:
            reg = json.load(fh)
        ops = reg["ops"]
        assert isinstance(ops, dict) and ops
    except (OSError, ValueError, KeyError, AssertionError) as exc:
        raise Fail(EXIT_ERR, f"registro de operaciones ilegible: {exc}")
    for name, op in ops.items():
        cls = op.get("effect_class")
        if cls not in ("read_only", "idempotent_remote", "non_idempotent"):
            raise Fail(EXIT_ERR, f"registro: {name} sin effect_class válida")
        if cls == "non_idempotent" and not (op.get("probe") in PROBES and op.get("pre_probe") is True):
            raise Fail(EXIT_ERR, f"registro: {name} es non_idempotent sin sonda previa (Regla 7b)")
        try:
            timeout, grace, lease = int(op["request_timeout_s"]), int(op["dispatch_grace_s"]), int(op["lease_s"])
        except (KeyError, TypeError, ValueError):
            raise Fail(EXIT_ERR, f"registro: {name} sin plazos")
        if grace < timeout + 60 or timeout <= 0 or lease <= 0:
            raise Fail(EXIT_ERR, f"registro: {name} exige dispatch_grace_s >= request_timeout_s + 60")
        for field, kind in op.get("args", {}).items():
            if not (kind in VALIDATORS or (isinstance(kind, dict) and isinstance(kind.get("enum"), list))):
                raise Fail(EXIT_ERR, f"registro: {name}.{field} con validador desconocido")
        if "{repo}" not in op.get("key", "") or "{number}" not in op.get("key", ""):
            raise Fail(EXIT_ERR, f"registro: {name} sin plantilla de clave")
    return ops


SEG = re.compile(r"^[A-Za-z0-9._-]+$")


def valid(kind, value):
    if not isinstance(value, str):
        return False
    if kind == "repo":
        parts = value.split("/")
        return len(parts) == 2 and all(SEG.match(p) and not p.startswith("-") and p not in (".", "..") for p in parts)
    if kind == "pr_number":
        return re.fullmatch(r"[1-9][0-9]{0,9}", value) is not None
    if kind == "sha40":
        return re.fullmatch(r"[0-9a-f]{40}", value) is not None
    if isinstance(kind, dict):
        return value in kind["enum"]
    return False


def build_args(op, raw):
    args = {}
    for field, kind in op["args"].items():
        value = raw.get(field)
        if not valid(kind, value):
            raise Fail(EXIT_ERR, f"argumento inválido: {field} (Regla 8)")
        args[field] = int(value) if kind == "pr_number" else value
    return args


def parse_key(op, key):
    m = re.fullmatch(r"([^#]+)#([^#]+)", key or "")
    if not m or not valid("repo", m.group(1)) or not valid("pr_number", m.group(2)):
        raise Fail(EXIT_ERR, "clave inválida (Regla 8)")
    return op["key"].format(repo=m.group(1), number=int(m.group(2)))


# ── Sonda de pr.merge (criterio cerrado 3b) ────────────────────────────────

def run_cmd(argv, timeout):
    try:
        cp = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
        return cp.returncode, cp.stdout
    except (OSError, subprocess.SubprocessError):
        return None, ""


def probe(op, args):
    """Devuelve dict con kind: OPEN_CLEAN | MERGED | UNKNOWN y lo observado."""
    fields = op["probe_fields"]
    rc, out = run_cmd(["gh", "pr", "view", str(args["number"]), "-R", args["repo"], "--json", ",".join(fields)],
                      op["request_timeout_s"])
    unknown = {"kind": "UNKNOWN", "rc": rc, "raw": (out or "")[:300]}
    if rc != 0:
        return unknown
    try:
        data = json.loads(out)
    except ValueError:
        return unknown
    if not isinstance(data, dict) or any(f not in data for f in fields):
        return unknown
    head = data.get("headRefOid")
    obs = {f: data[f] for f in fields}
    if data["state"] == "OPEN" and all(data[f] is None for f in ("mergedAt", "mergeCommit", "mergedBy", "autoMergeRequest")) \
            and isinstance(head, str) and head:
        return {"kind": "OPEN_CLEAN", "head": head, "obs": obs}
    mc, by = data.get("mergeCommit"), data.get("mergedBy")
    commit = mc.get("oid") if isinstance(mc, dict) else mc
    login = by.get("login") if isinstance(by, dict) else None
    if data["state"] == "MERGED" and data["mergedAt"] and commit and isinstance(login, str) and login.strip():
        return {"kind": "MERGED", "head": head, "commit": commit, "login": login, "obs": obs}
    return unknown


def present_match(res, args, actor_remote):
    return (res["kind"] == "MERGED" and res["head"] == args.get("head")
            and isinstance(actor_remote, str) and res["login"].lower() == actor_remote.lower())


def absent(res, args):
    return res["kind"] == "OPEN_CLEAN" and res["head"] == args.get("head")


# ── Identidad (perfil activo y remoto, Regla 6b) ───────────────────────────

def active_actor():
    path = os.environ.get("SAVIA_ACTIVE_USER_FILE") or os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), ".claude", "profiles", "active-user.md")
    try:
        with open(path, encoding="utf-8") as fh:
            m = re.search(r'active_slug:\s*"([^"]+)"', fh.read())
    except OSError:
        return None
    return m.group(1) if m else None


def remote_identity(op):
    rc, out = run_cmd(op["identity_cmd"], op["request_timeout_s"])
    login = (out or "").strip()
    return login if rc == 0 and login and "\n" not in login else None


def holder_start(env, pid):
    if pid is None or pid <= 1:
        return None
    try:
        with open(os.path.join(env.proc_root(), str(pid), "stat"), encoding="utf-8") as fh:
            stat = fh.read()
        fields = stat[stat.rindex(")") + 2:].split()
        # Un zombi (Z) o un proceso ya muerto (X) no sostiene la reclamación.
        return None if fields[0] in ("Z", "X") else fields[19]
    except (OSError, ValueError, IndexError):
        return None


# ── Ledger SQLite ──────────────────────────────────────────────────────────

def tighten(path, mode):
    """Cierra a `mode` un fichero o directorio existente con permisos más amplios."""
    try:
        st = os.stat(path)
    except FileNotFoundError:
        return
    if st.st_mode & 0o777 & ~mode == 0:
        return
    if st.st_uid != os.getuid():
        warn(f"{path} tiene permisos {oct(st.st_mode & 0o777)} y no es tuyo: no se pueden cerrar a {oct(mode)}")
        return
    os.chmod(path, mode)


class Ledger:
    def __init__(self, env):
        self.env = env
        busy = env.hook("SAVIA_EFFECT_BUSY_MS")
        self.busy_s = (int(busy) / 1000.0) if busy.isdigit() else 10.0
        lock = None
        try:
            # El ledger guarda logins, actor y tokens: solo la persona dueña lo lee (0600/0700).
            os.umask(0o077)
            os.makedirs(os.path.dirname(env.path), mode=0o700, exist_ok=True)
            real = os.path.realpath(env.path)
            # La umask solo cubre lo nuevo: lo que ya existía con permisos más abiertos se cierra.
            tighten(os.path.dirname(real), 0o700)
            # Apertura serializada: cambiar a WAL un fichero nuevo devuelve BUSY sin esperar
            # al busy_timeout si otro proceso lo inicializa a la vez. Lock junto al fichero real.
            lock = open(real + ".lock", "a", encoding="utf-8")
            self._flock(lock)
            for f in (real, real + ".lock"):
                tighten(f, 0o600)
            self.db = sqlite3.connect(env.path, timeout=self.busy_s, isolation_level=None)
            self.db.row_factory = sqlite3.Row
            self.db.execute("PRAGMA journal_mode=WAL")
            for f in (real + "-wal", real + "-shm"):
                tighten(f, 0o600)
            self.db.execute("PRAGMA synchronous=FULL")
            if env.hook("SAVIA_EFFECT_FAULT") == "pragma_normal":
                self.db.execute("PRAGMA synchronous=NORMAL")
            jm = self.db.execute("PRAGMA journal_mode").fetchone()[0]
            sync = self.db.execute("PRAGMA synchronous").fetchone()[0]
            if str(jm).lower() != "wal" or int(sync) != 2:
                raise Fail(EXIT_ERR, f"durabilidad no garantizada (journal_mode={jm}, synchronous={sync}); no se escribe (Regla 1)")
            self.db.execute("BEGIN IMMEDIATE")
            for stmt in SCHEMA.strip().split(";"):
                if stmt.strip():
                    self.db.execute(stmt)
            cols = tuple(r[1] for r in self.db.execute("PRAGMA table_info(effects)"))
            ver = self.db.execute("SELECT v FROM meta WHERE k='schema_version'").fetchone()
            if ver is None and not self.db.execute("SELECT 1 FROM effects LIMIT 1").fetchone():
                self.db.execute("INSERT INTO meta VALUES ('schema_version', ?)", (SCHEMA_VERSION,))
                self.db.execute("INSERT INTO meta VALUES ('install_id', ?)", (str(uuid.uuid4()),))
                ver = (SCHEMA_VERSION,)
            if ver is None or ver[0] != SCHEMA_VERSION or cols != EFFECT_COLS:
                self.db.execute("ROLLBACK")
                raise Fail(EXIT_ERR, "esquema del ledger desconocido; no se toca")
            self.install_id = self.db.execute("SELECT v FROM meta WHERE k='install_id'").fetchone()[0]
            self.db.execute("COMMIT")
        except (sqlite3.Error, OSError) as exc:
            raise Fail(EXIT_ERR, f"ledger ilegible, bloqueado o sin escritura: {exc}")
        finally:
            if lock is not None:
                lock.close()

    def _flock(self, fh):
        deadline = time.monotonic() + self.busy_s
        while True:
            try:
                fcntl.flock(fh, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return
            except BlockingIOError:
                if time.monotonic() >= deadline:
                    raise Fail(EXIT_ERR, "ledger bloqueado más allá del timeout")
                time.sleep(0.02)

    def begin(self):
        self.db.execute("BEGIN IMMEDIATE")

    def commit(self):
        self.db.execute("COMMIT")

    def rollback(self):
        if self.db.in_transaction:
            self.db.execute("ROLLBACK")

    def current(self, op, key):
        return self.db.execute("SELECT * FROM effects WHERE op=? AND idempotency_key=? ORDER BY attempt DESC LIMIT 1",
                               (op, key)).fetchone()

    def by_id(self, eid):
        return self.db.execute("SELECT * FROM effects WHERE effect_id=?", (eid,)).fetchone()

    def event(self, eid, name, detail=None):
        self.db.execute("INSERT INTO events (effect_id, ts, event, detail) VALUES (?,?,?,?)",
                        (eid, self.env.now(), name, canon(detail) if detail is not None else None))

    def update(self, eid, **fields):
        fields["updated_at"] = self.env.now()
        cols = ", ".join(f"{k}=?" for k in fields)
        self.db.execute(f"UPDATE effects SET {cols} WHERE effect_id=?", (*fields.values(), eid))  # nosec: columnas fijas

    def insert(self, **fields):
        now = self.env.now()
        fields.setdefault("created_at", now)
        fields.setdefault("updated_at", now)
        cols = ", ".join(fields)
        marks = ", ".join("?" for _ in fields)
        self.db.execute(f"INSERT INTO effects ({cols}) VALUES ({marks})", tuple(fields.values()))  # nosec: columnas fijas

    def add_receipt(self, row, args, evidence, attribution, unverified):
        last = self.db.execute("SELECT hash FROM receipts ORDER BY seq DESC LIMIT 1").fetchone()
        prev = last[0] if last else GENESIS
        body = canon({
            "effect_id": row["effect_id"], "op": row["op"], "key": row["idempotency_key"],
            "args_digest": row["args_digest"], "actor": row["actor"], "install_id": row["install_id"],
            "outcome": "succeeded", "evidence": evidence, "unverified": unverified,
            "attribution": attribution, "observed_at": self.env.now(), "prev_hash": prev})
        self.db.execute("INSERT INTO receipts (effect_id, body, prev_hash, hash) VALUES (?,?,?,?)",
                        (row["effect_id"], body, prev, sha256(body)))
        return body


def snapshot(row):
    return None if row is None else (row["effect_id"], row["state"], row["attempt"], row["claim_token"])


def evidence_from(res):
    return {"merge_commit": res.get("commit"), "mergedBy": res.get("login"), "headRefOid": res.get("head")}


def claim_live(led, row, now):
    if row["install_id"] != led.install_id or row["holder_pid"] is None:
        return (row["lease_until"] or 0) > now
    return holder_start(led.env, row["holder_pid"]) == row["holder_start"]


def grace_passed(op, row, now):
    return now >= (row["dispatched_at"] or 0) + op["dispatch_grace_s"]


def succeed(led, op, row, res, attribution):
    args = json.loads(row["args"])
    evidence = evidence_from(res)
    # El recibo no afirma más de lo observado: lo que falta en la evidencia queda como no verificado.
    unverified = list(op.get("unverified", [])) + sorted(k for k, v in evidence.items() if v is None)
    body = led.add_receipt(row, args, evidence, attribution, unverified)
    led.update(row["effect_id"], state="SUCCEEDED", receipt=body, observation=canon(res.get("obs")),
               claim_token=None)
    led.event(row["effect_id"], "SUCCEEDED", {"attribution": attribution})
    return body


def review(led, row, origin, res):
    led.update(row["effect_id"], state="NEEDS_REVIEW", review_origin=origin,
               observation=canon(res.get("obs") or {"raw": res.get("raw"), "rc": res.get("rc")}), claim_token=None)
    led.event(row["effect_id"], "NEEDS_REVIEW", {"origin": origin})


def fail_row(led, row, failure, res=None):
    led.update(row["effect_id"], state="FAILED", failure=failure, claim_token=None,
               observation=canon(res.get("obs")) if res and res.get("obs") else row["observation"])
    led.event(row["effect_id"], "FAILED", {"failure": failure})


def judge_dispatched(op, row, res, now):
    """Tabla de la Regla 3 para un DISPATCHED. Devuelve SUCCEEDED|REVIEW|REJECTED|FAILED|WAIT."""
    args = json.loads(row["args"])
    if res["kind"] == "MERGED":
        if present_match(res, args, row["actor_remote"]):
            return "REJECTED" if row["dispatch_rejected"] else "SUCCEEDED"
        return "REVIEW"
    if not grace_passed(op, row, now):
        return "WAIT"
    return "FAILED" if absent(res, args) else "REVIEW"


def apply_judgement(led, op, row, res, verdict):
    if verdict == "SUCCEEDED":
        succeed(led, op, row, res, "probe")
    elif verdict == "REJECTED":
        review(led, row, "rejected", res)
    elif verdict == "REVIEW":
        review(led, row, "dispatched", res)
    elif verdict == "FAILED":
        fail_row(led, row, "absent_after_grace", res)


# ── Órdenes ────────────────────────────────────────────────────────────────

def out(*parts):
    print(" ".join(str(p) for p in parts))


def new_claim(led, op, opname, key, args, attempt, ctx):
    token = secrets.token_hex(16)
    eid = str(uuid.uuid4())
    led.insert(effect_id=eid, op=opname, idempotency_key=key, attempt=attempt, state="PREPARED",
               args=canon(args), args_digest=sha256(canon(args)), effect_class=op["effect_class"],
               install_id=led.install_id, actor=ctx["actor"], actor_remote=ctx["identity"], run_id=ctx["run_id"],
               claim_token=token, lease_until=ctx["now"] + op["lease_s"], holder_pid=ctx["hpid"],
               holder_start=ctx["hstart"])
    led.event(eid, "PREPARED", {"attempt": attempt})
    return eid, token


def reclaim(led, op, row, ctx):
    token = secrets.token_hex(16)
    led.update(row["effect_id"], claim_token=token, lease_until=ctx["now"] + op["lease_s"], holder_pid=ctx["hpid"],
               holder_start=ctx["hstart"], actor_remote=ctx["identity"], actor=ctx["actor"], run_id=ctx["run_id"])
    led.event(row["effect_id"], "RECLAIMED")
    return row["effect_id"], token


def only_head_differs(old, new):
    return set(k for k in set(old) | set(new) if old.get(k) != new.get(k)) == {"head"}


def decide_prepare(led, op, opname, key, args, row, res, ctx):
    """Aplica la tabla de prepare dentro de la transacción. Devuelve (exit, línea)."""
    now, digest = ctx["now"], sha256(canon(args))

    def proceed(attempt, prev=None):
        if not ctx["identity"]:
            return EXIT_ERR, "ERROR sin identidad remota: no se reclama (Regla 6b)"
        eid, token = new_claim(led, op, opname, key, args, attempt, ctx)
        return EXIT_OK, f"PROCEED {eid} {token}"

    if row is None:
        return proceed(1)
    st, eid = row["state"], row["effect_id"]
    old = json.loads(row["args"])
    same = row["args_digest"] == digest
    live = st == "PREPARED" and claim_live(led, row, now)
    if not same:
        if st == "NEEDS_REVIEW":
            return EXIT_REVIEW, f"NEEDS_REVIEW {eid} review_origin={row['review_origin']}"
        if live:
            return EXIT_INFLIGHT, f"IN_FLIGHT {eid}"
        if not (op.get("head_pinned") and only_head_differs(old, args)) or st == "SUCCEEDED":
            return EXIT_CONFLICT, f"CONFLICT {eid}"
        if st in ("FAILED", "PREPARED"):
            if st == "PREPARED":
                fail_row(led, row, "abandoned_unsent")
            return proceed(row["attempt"] + 1)
        # DISPATCHED con otro head (2d.3)
        if res["kind"] == "OPEN_CLEAN" and res["head"] == args["head"] and res["head"] != old.get("head"):
            fail_row(led, row, "superseded", res)
            return proceed(row["attempt"] + 1)
    if st == "SUCCEEDED":
        sys.stdout.write(f"ALREADY_EXECUTED {eid}\n{row['receipt']}\n")
        return EXIT_DONE, None
    if st == "NEEDS_REVIEW":
        return EXIT_REVIEW, f"NEEDS_REVIEW {eid} review_origin={row['review_origin']}"
    if st == "FAILED":
        return proceed(row["attempt"] + 1)
    if st == "PREPARED":
        if live:
            return EXIT_INFLIGHT, f"IN_FLIGHT {eid}"
        if not ctx["identity"]:
            return EXIT_ERR, "ERROR sin identidad remota: no se reclama (Regla 6b)"
        eid, token = reclaim(led, op, row, ctx)
        return EXIT_OK, f"PROCEED {eid} {token}"
    # DISPATCHED: Regla 3
    verdict = judge_dispatched(op, row, res, now)
    apply_judgement(led, op, row, res, verdict)
    if verdict == "SUCCEEDED":
        sys.stdout.write(f"ALREADY_EXECUTED {eid}\n{led.by_id(eid)['receipt']}\n")
        return EXIT_DONE, None
    if verdict in ("REVIEW", "REJECTED"):
        return EXIT_REVIEW, f"NEEDS_REVIEW {eid} review_origin={'rejected' if verdict == 'REJECTED' else 'dispatched'}"
    if verdict == "WAIT":
        return EXIT_INFLIGHT, f"IN_FLIGHT {eid}"
    return proceed(row["attempt"] + 1)


def cmd_prepare(env, ops, a):
    opname = a.pos(0)
    op = ops.get(opname) or fail2(f"op no registrada: {opname}")
    args = build_args(op, a.opts)
    key = op["key"].format(**args)
    actor = active_actor()
    hpid_raw = a.opts.get("holder-pid")
    if op["effect_class"] == "non_idempotent":
        if not actor:
            raise Fail(EXIT_ERR, "sin perfil activo: un efecto non_idempotent falla cerrado")
        if not hpid_raw:
            raise Fail(EXIT_ERR, "--holder-pid obligatorio para efectos non_idempotent (Regla 2b)")
    if hpid_raw is not None and not re.fullmatch(r"[0-9]{1,10}", hpid_raw):
        raise Fail(EXIT_ERR, "--holder-pid inválido")
    run_id = a.opts.get("run-id")
    if run_id is not None and not re.fullmatch(r"[A-Za-z0-9._:-]{1,128}", run_id):
        raise Fail(EXIT_ERR, "--run-id inválido")
    hpid = int(hpid_raw) if hpid_raw else None
    hstart = holder_start(env, hpid)
    if hstart is None:
        hpid = None
    led = Ledger(env)
    row = led.current(opname, key)
    snap = snapshot(row)
    # Fuera de transacción: sonda (red) e identidad remota.
    res = probe(op, args) if row is not None and row["state"] == "DISPATCHED" else None
    may_claim = row is None or row["state"] in ("PREPARED", "FAILED", "DISPATCHED")
    ctx = {"now": env.now(), "actor": actor, "run_id": run_id, "hpid": hpid, "hstart": hstart,
           "identity": remote_identity(op) if may_claim else None}
    led.begin()
    try:
        row = led.current(opname, key)
        if snapshot(row) != snap:
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {row['effect_id'] if row else '-'} (la entrada cambió durante la sonda)"
        code, line = decide_prepare(led, op, opname, key, args, row, res, ctx)
        led.commit()
    except BaseException:
        led.rollback()
        raise
    if code == EXIT_OK:
        env.fault("after_prepare")
    return code, line


def fail2(msg):
    raise Fail(EXIT_ERR, msg)


def load_row(led, ops, eid):
    if not eid or not re.fullmatch(r"[0-9a-f-]{36}", eid):
        raise Fail(EXIT_ERR, "effect_id inválido")
    row = led.by_id(eid)
    if row is None:
        raise Fail(EXIT_ERR, f"effect_id inexistente: {eid}")
    op = ops.get(row["op"]) or fail2(f"op no registrada: {row['op']}")
    return row, op


def cmd_dispatch(env, ops, a):
    led = Ledger(env)
    eid, token = a.pos(0), a.need("claim")
    row, op = load_row(led, ops, eid)
    if row["claim_token"] != token:
        return EXIT_INFLIGHT, f"IN_FLIGHT {eid} (token no vigente: no envíes)"
    if row["state"] != "PREPARED":
        raise Fail(EXIT_ERR, f"dispatch no admitido desde {row['state']}")
    snap = snapshot(row)
    res = probe(op, json.loads(row["args"])) if op.get("pre_probe") else {"kind": "SKIP"}
    led.begin()
    try:
        row = led.by_id(eid)
        if snapshot(row) != snap:
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {eid} (la entrada cambió durante la sonda previa)"
        if res["kind"] == "MERGED":
            review(led, row, "pre_probe", res)
            led.commit()
            return EXIT_REVIEW, f"NEEDS_REVIEW {eid} review_origin=pre_probe"
        if res["kind"] != "SKIP" and not absent(res, json.loads(row["args"])):
            led.rollback()
            raise Fail(EXIT_ERR, f"sonda previa no concluyente: no se envía; {eid} sigue PREPARED (3c)")
        cur = led.db.execute(
            "UPDATE effects SET state='DISPATCHED', dispatched_at=?, updated_at=? "
            "WHERE effect_id=? AND state='PREPARED' AND claim_token=?", (env.now(), env.now(), eid, token))
        if cur.rowcount != 1:
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {eid} (CAS perdido: no envíes)"
        led.event(eid, "DISPATCHED")
        led.commit()
    except BaseException:
        led.rollback()
        raise
    env.fault("after_dispatch")
    return EXIT_OK, f"DISPATCHED {eid}"


def owned_dispatched(led, ops, a, states=("DISPATCHED",)):
    row, op = load_row(led, ops, a.pos(0))
    if row["state"] not in states or row["claim_token"] != a.need("claim"):
        raise Fail(EXIT_ERR, f"{a.cmd} no admitido: estado {row['state']} o token ajeno")
    return row, op


def cmd_complete(env, ops, a):
    led = Ledger(env)
    led.begin()
    try:
        row, op = owned_dispatched(led, ops, a)
        try:
            resp = json.loads(a.need("response"))
        except ValueError:
            resp = None
        ev = resp.get(op["response_evidence"]) if isinstance(resp, dict) else None
        commit = ev.get("oid") if isinstance(ev, dict) else ev
        if not (isinstance(commit, str) and commit.strip()):
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {row['effect_id']} (respuesta sin {op['response_evidence']}: la cierra la sonda)"
        if not valid("sha40", commit):
            # La evidencia del recibo es un commit; una cadena arbitraria no lo es.
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {row['effect_id']} ({op['response_evidence']} no es un sha de 40 hex: la cierra la sonda)"
        if row["dispatch_rejected"]:
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {row['effect_id']} (rechazo anotado: solo la sonda lo cierra, 3e)"
        by = resp.get("mergedBy")
        login = by.get("login") if isinstance(by, dict) else by
        head = resp.get("headRefOid")
        args = json.loads(row["args"])
        if (head is not None and head != args.get("head")) or (
                login is not None and str(login).lower() != str(row["actor_remote"] or "").lower()):
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {row['effect_id']} (la respuesta contradice la entrada: la cierra la sonda)"
        res = {"commit": commit, "login": login, "head": head, "obs": resp}
        env.fault("before_complete")
        succeed(led, op, row, res, "response")
        led.commit()
    except BaseException:
        led.rollback()
        raise
    return EXIT_OK, f"SUCCEEDED {row['effect_id']}"


def cmd_reject(env, ops, a):
    led = Ledger(env)
    led.begin()
    try:
        row, _ = owned_dispatched(led, ops, a)
        led.update(row["effect_id"], dispatch_rejected=1, reject_response=a.need("response")[:2000])
        led.event(row["effect_id"], "REJECTED_ANNOTATED")
        led.commit()
    except BaseException:
        led.rollback()
        raise
    return EXIT_INFLIGHT, f"IN_FLIGHT {row['effect_id']} (rechazo anotado; lo cierra la sonda, 3e)"


def cmd_fail(env, ops, a):
    led = Ledger(env)
    led.begin()
    try:
        row, _ = owned_dispatched(led, ops, a, states=("PREPARED",))
        led.update(row["effect_id"], state="FAILED", failure="aborted: " + a.need("reason")[:500], claim_token=None)
        led.event(row["effect_id"], "FAILED", {"failure": "aborted"})
        led.commit()
    except BaseException:
        led.rollback()
        raise
    return EXIT_OK, f"FAILED {row['effect_id']}"


def receipt_head(row):
    try:
        return json.loads(row["receipt"])["evidence"].get("headRefOid") or "-"
    except (TypeError, ValueError, KeyError, AttributeError):
        return "-"


def cmd_reconcile(env, ops, a):
    opname = a.opts.get("op", "pr.merge")
    op = ops.get(opname) or fail2(f"op no registrada: {opname}")
    key = parse_key(op, a.pos(0))
    led = Ledger(env)
    row = led.current(opname, key)

    def line(result, r, head="-", extra=""):
        return " ".join(x for x in (result, r["effect_id"] if r else "-", (r["run_id"] or "-") if r else "-", head, extra) if x)

    if row is None:
        return EXIT_OK, line("NOT_SENT", None)
    st = row["state"]
    if st == "SUCCEEDED":
        return EXIT_ALREADY, line("ALREADY_SUCCEEDED", row, receipt_head(row))
    if st == "NEEDS_REVIEW":
        return EXIT_REVIEW, line("NEEDS_REVIEW", row, "-", f"review_origin={row['review_origin']}")
    if st == "FAILED":
        return EXIT_OK, line("NOT_SENT", row)
    if st == "PREPARED":
        live = claim_live(led, row, env.now())
        return (EXIT_INFLIGHT, line("IN_FLIGHT", row)) if live else (EXIT_OK, line("NOT_SENT", row))
    snap = snapshot(row)
    res = probe(op, json.loads(row["args"]))
    led.begin()
    try:
        row = led.current(opname, key)
        if snapshot(row) != snap:
            led.rollback()
            return EXIT_INFLIGHT, line("IN_FLIGHT", row)
        verdict = judge_dispatched(op, row, res, env.now())
        apply_judgement(led, op, row, res, verdict)
        led.commit()
    except BaseException:
        led.rollback()
        raise
    row = led.by_id(row["effect_id"])
    if verdict == "SUCCEEDED":
        return EXIT_DONE, line("RECONCILED", row, receipt_head(row))
    if verdict in ("REVIEW", "REJECTED"):
        return EXIT_REVIEW, line("NEEDS_REVIEW", row, "-", f"review_origin={row['review_origin']}")
    if verdict == "WAIT":
        return EXIT_INFLIGHT, line("IN_FLIGHT", row)
    return EXIT_OK, line("NOT_SENT", row)


def cmd_resolve(env, ops, a):
    by_probe, manual = a.flags.get("by-probe", False), a.flags.get("manual", False)
    if by_probe == manual:
        raise Fail(EXIT_ERR, "resolve exige exactamente una ruta: --by-probe o --manual")
    if manual:
        if os.environ.get("SAVIA_AUTONOMOUS_RUN") == "1":
            raise Fail(EXIT_ERR, "la ruta manual es de una persona: rechazada con SAVIA_AUTONOMOUS_RUN=1")
        raise Fail(EXIT_ERR, "ruta manual no disponible en S1: llega en S2 con el scope effect-resolve de operator-grant.sh")
    if "evidence" in a.opts:
        raise Fail(EXIT_ERR, "--evidence no se admite en la ruta por sonda")
    outcome = a.opts.get("outcome")
    if outcome not in (None, "succeeded", "failed"):
        raise Fail(EXIT_ERR, "--outcome debe ser succeeded o failed")
    led = Ledger(env)
    row, op = load_row(led, ops, a.pos(0))
    if row["state"] != "NEEDS_REVIEW":
        raise Fail(EXIT_ERR, f"resolve solo desde NEEDS_REVIEW (estado {row['state']})")
    if row["review_origin"] != "dispatched":
        raise Fail(EXIT_ERR, f"review_origin={row['review_origin']}: este ledger no pidió ese efecto; solo ruta manual con grant (Regla 5)")
    snap = snapshot(row)
    args = json.loads(row["args"])
    res = probe(op, args)
    now = env.now()
    if present_match(res, args, row["actor_remote"]):
        if row["dispatch_rejected"]:
            # 3e: un rechazo anotado nunca deja cerrar como propio un PRESENT posterior,
            # aunque la fila llegara a revisión por la rama UNKNOWN (origen dispatched).
            raise Fail(EXIT_ERR, "rechazo anotado y efecto presente: este ledger no lo pidió con éxito; "
                                 "solo ruta manual con grant (Reglas 3e y 5)")
        verdict = "succeeded"
    elif absent(res, args) and grace_passed(op, row, now):
        verdict = "failed"
    else:
        verdict = None
    if verdict is None:
        return EXIT_REVIEW, f"NEEDS_REVIEW {row['effect_id']} review_origin=dispatched (la sonda no concluye)"
    if outcome is not None and outcome != verdict:
        raise Fail(EXIT_ERR, f"--outcome {outcome} contradice la sonda ({verdict}); no se escribe")
    led.begin()
    try:
        row = led.by_id(row["effect_id"])
        if snapshot(row) != snap:
            led.rollback()
            return EXIT_INFLIGHT, f"IN_FLIGHT {row['effect_id']}"
        resolution = canon({"route": "by-probe", "by": active_actor() or "-", "grant": None,
                            "evidence": res.get("obs"), "at": now})
        if verdict == "succeeded":
            succeed(led, op, row, res, "probe")
        else:
            fail_row(led, row, "absent_after_grace", res)
        led.update(row["effect_id"], resolution=resolution)
        led.event(row["effect_id"], "RESOLVED", {"route": "by-probe", "outcome": verdict})
        led.commit()
    except BaseException:
        led.rollback()
        raise
    return EXIT_OK, f"{verdict.upper()} {row['effect_id']} route=by-probe"


def row_json(row):
    # El token es la capacidad de dispatch/complete (Regla 2b): nunca sale del proceso que reclamó.
    view = {k: row[k] for k in row.keys() if k != "claim_token"}
    view["claim_held"] = row["claim_token"] is not None
    return canon(view)


def cmd_status(env, ops, a):
    led = Ledger(env)
    if a.flags.get("open"):
        for r in led.db.execute("SELECT * FROM effects WHERE state IN ('PREPARED','DISPATCHED','NEEDS_REVIEW') "
                                "ORDER BY created_at"):
            print(row_json(r))
        return EXIT_OK, None
    opname = a.opts.get("op", "pr.merge")
    op = ops.get(opname) or fail2(f"op no registrada: {opname}")
    row = led.current(opname, parse_key(op, a.pos(0)))
    return EXIT_OK, row_json(row) if row else "none"


def cmd_verify(env, ops, a):
    led = Ledger(env)
    row, op = load_row(led, ops, a.pos(0))
    rec = led.db.execute("SELECT * FROM receipts WHERE effect_id=?", (row["effect_id"],)).fetchone()
    if rec is None:
        raise Fail(EXIT_ERR, f"{row['effect_id']} sin recibo")
    prev = GENESIS
    for r in led.db.execute("SELECT * FROM receipts ORDER BY seq"):
        try:
            body_prev = json.loads(r["body"]).get("prev_hash")
        except ValueError:
            body_prev = None
        if r["prev_hash"] != prev or body_prev != prev or sha256(r["body"]) != r["hash"]:
            return EXIT_FAIL, f"FAIL cadena alterada en el recibo seq={r['seq']}"
        prev = r["hash"]
    body = json.loads(rec["body"])
    ev = body["evidence"]
    res = probe(op, json.loads(row["args"]))
    note = "unverified: " + (",".join(body.get("unverified") or []) or "-")
    if res["kind"] == "UNKNOWN":
        return EXIT_REVIEW, f"UNVERIFIED {row['effect_id']} cadena íntegra, sonda no concluyente; {note}"
    if res["kind"] == "MERGED" and ev.get("merge_commit") and res["commit"] == ev["merge_commit"] \
            and ev.get("headRefOid") in (None, res["head"]) \
            and (ev.get("mergedBy") is None or res["login"].lower() == str(ev["mergedBy"]).lower()):
        return EXIT_OK, f"VERIFIED {row['effect_id']} {note}"
    return EXIT_FAIL, f"FAIL {row['effect_id']} el remoto contradice el recibo"


# ── Argumentos ─────────────────────────────────────────────────────────────

FLAGS = {"by-probe", "manual", "open"}


class Args:
    def __init__(self, argv):
        self.cmd = argv[0] if argv else ""
        self.positional, self.opts, self.flags = [], {}, {}
        it = iter(argv[1:])
        for tok in it:
            if tok.startswith("--"):
                name = tok[2:]
                if name in FLAGS:
                    self.flags[name] = True
                    continue
                val = next(it, None)
                if val is None or name in self.opts:
                    raise Fail(EXIT_ERR, f"opción sin valor o repetida: {tok}")
                self.opts[name] = val
            else:
                self.positional.append(tok)

    def pos(self, i):
        if len(self.positional) <= i:
            raise Fail(EXIT_ERR, f"{self.cmd}: falta argumento posicional")
        return self.positional[i]

    def need(self, name):
        if name not in self.opts:
            raise Fail(EXIT_ERR, f"{self.cmd}: falta --{name}")
        return self.opts[name]


COMMANDS = {
    "prepare": cmd_prepare, "dispatch": cmd_dispatch, "complete": cmd_complete, "reject": cmd_reject,
    "fail": cmd_fail, "reconcile": cmd_reconcile, "resolve": cmd_resolve, "status": cmd_status,
    "verify-receipt": cmd_verify,
}


def main(argv):
    try:
        a = Args(argv)
        if a.cmd not in COMMANDS:
            raise Fail(EXIT_ERR, "uso: effect-ledger.py " + "|".join(COMMANDS) + " … (ver cabecera)")
        env = Env()
        ops = load_registry(env)
        code, line = COMMANDS[a.cmd](env, ops, a)
        if line:
            print(line)
        return code
    except Fail as exc:
        if exc.msg:
            print(f"ERROR {exc.msg}" if exc.code == EXIT_ERR else exc.msg, file=sys.stderr)
        return exc.code
    except sqlite3.Error as exc:
        print(f"ERROR ledger: {exc}", file=sys.stderr)
        return EXIT_ERR
    except Exception as exc:  # noqa: BLE001 — un fallo interno nunca debe leerse como veredicto (1)
        print(f"ERROR interno: {type(exc).__name__}: {exc}", file=sys.stderr)
        return EXIT_ERR


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
