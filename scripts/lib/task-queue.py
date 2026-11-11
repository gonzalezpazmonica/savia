#!/usr/bin/env python3
"""task-queue.py — SE-075 Slice 1.

Serial-execution job queue with SQLite persistence and auto-recovery of
stale (running) jobs at startup. Re-implementation of the pattern in
`jamiepine/voicebox` `backend/services/task_queue.py` (MIT license, ©
voicebox contributors); this is a clean-room rewrite — no source code is
copied — adapted to bash + python rather than the original FastAPI runtime.

Attribution: pattern from voicebox/backend/services/task_queue.py (MIT).

Storage:
  output/task-queue/<queue_name>.sqlite

Usage (CLI):
  python3 scripts/lib/task-queue.py enqueue <queue> <command> [--payload JSON]
  python3 scripts/lib/task-queue.py dequeue <queue> [--worker WORKER]
  python3 scripts/lib/task-queue.py complete <queue> <job_id> [--ok|--fail MSG]
  python3 scripts/lib/task-queue.py status <queue> [--json]
  python3 scripts/lib/task-queue.py recover <queue>
  python3 scripts/lib/task-queue.py drain <queue>           # delete completed jobs

  SE-513 S1 — admisión duradera de cambios de intención (misma cola, mismo
  fichero SQLite; la admisión y su salida van en una sola transacción):
  python3 scripts/lib/task-queue.py admit <queue> --text T --origin O [--job ID]
         [--bump N] [--set-text T] [--signal plan|none] [--kind change|new_work]
  python3 scripts/lib/task-queue.py pull <queue> --owner AGENTE   # entrega al terminar el paso
  python3 scripts/lib/task-queue.py ack <queue> <id> [--plan-proof JSON]
  python3 scripts/lib/task-queue.py changes <queue> [--all] [--json]
  Estados: ADMITTED (persistido y con dueño), APPLIED_TO_PLAN (solo con prueba
  del plan del agente), UNKNOWN (sin prueba). Sin prueba nunca hay APPLIED.
  Límites de S1: `--origin` y la prueba de plan son DECLARACIONES de quien llama
  (proceso local); la cola no las autentica ni las firma. Solo exige que la
  prueba la declare el agente que recibió el cambio (entregado por `pull`).
  `ack` tampoco autentica a quien llama. `effect_permission=PENDING` es una
  etiqueta: el ejecutor que consuma `dequeue` DEBE comprobarla antes de
  ejecutar el efecto; la cola no lo hace (identidad atada: SE-514).

  SE-513 S2 — promoción por regla (solo lectura, sin almacén nuevo):
  python3 scripts/lib/task-queue.py promote <queue> [--json]
  Cada cambio admitido sube a LOCAL, COORDINACION o HUMANO leyendo SOLO campos
  estructurados (origen, tipo, estado, efecto, dependencias y acl del trabajo);
  el texto libre nunca cuenta. Ante entrada inesperada se queda en LOCAL.

Programmatic (sourced from other Python):
  from task_queue import TaskQueue
  q = TaskQueue("se074-orchestrator")
  job_id = q.enqueue("run-spec", payload={"spec": "SE-073"})
  job = q.dequeue(worker="worker-1")
  q.complete(job["id"], ok=True)

Reference: SE-075 Slice 1 (docs/propuestas/SE-075-voicebox-adoption.md)
Reference: SE-513 S1 (docs/specs/SE-513-admision-duradera-y-comprobacion-previa.spec.md)
Reference: docs/rules/domain/autonomous-safety.md
"""
from __future__ import annotations

import argparse
import hashlib
import unicodedata
import json
import os
import re
import sqlite3
import sys
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator

ROOT = Path(os.environ.get("PROJECT_ROOT", str(Path(__file__).resolve().parents[2])))
DEFAULT_QUEUE_DIR = ROOT / "output" / "task-queue"
STALE_HEARTBEAT_SEC = int(os.environ.get("TASK_QUEUE_STALE_SEC", "300"))


def _queue_path(queue_name: str, queue_dir: Path = DEFAULT_QUEUE_DIR) -> Path:
    queue_dir.mkdir(parents=True, exist_ok=True)
    safe = "".join(c for c in queue_name if c.isalnum() or c in "._-")
    if not safe:
        raise ValueError(f"invalid queue name: {queue_name!r}")
    return queue_dir / f"{safe}.sqlite"


_SCHEMA = """
CREATE TABLE IF NOT EXISTS jobs (
    id          TEXT PRIMARY KEY,
    queue       TEXT NOT NULL,
    command     TEXT NOT NULL,
    payload     TEXT,
    status      TEXT NOT NULL DEFAULT 'pending',  -- pending | running | done | failed
    worker      TEXT,
    error       TEXT,
    created_at  REAL NOT NULL,
    started_at  REAL,
    finished_at REAL,
    heartbeat   REAL
);
CREATE INDEX IF NOT EXISTS jobs_queue_status_created
    ON jobs (queue, status, created_at);
CREATE TABLE IF NOT EXISTS admissions (
    seq            INTEGER PRIMARY KEY AUTOINCREMENT,
    queue          TEXT NOT NULL,
    dedup_key      TEXT NOT NULL,
    text           TEXT NOT NULL,
    origin         TEXT NOT NULL,
    kind           TEXT NOT NULL,      -- change | context
    state          TEXT NOT NULL,      -- ADMITTED | APPLIED_TO_PLAN | UNKNOWN | CONTEXT
    owner          TEXT,
    job_id         TEXT,
    bump           INTEGER NOT NULL DEFAULT 0,
    set_text       TEXT,
    signal         TEXT NOT NULL DEFAULT 'plan',
    effect         TEXT,
    effect_permission TEXT,            -- PENDING si el trabajo tiene efecto; nunca se concede aquí
    reason         TEXT,
    proof          TEXT,
    repeats        INTEGER NOT NULL DEFAULT 0,
    recovered      INTEGER NOT NULL DEFAULT 0,
    created_at     REAL NOT NULL,
    last_repeat_at REAL,
    delivered_at   REAL,
    acked_at       REAL,
    applied_at     REAL,
    UNIQUE (queue, dedup_key)
);
"""

# SE-513 — estados de una admisión. CONTEXT no es una obligación: es lo que
# llega de un origen no autenticado y se guarda solo para explicar.
ADMITTED, APPLIED, UNKNOWN, CONTEXT = "ADMITTED", "APPLIED_TO_PLAN", "UNKNOWN", "CONTEXT"
AUTH_ORIGINS = {"operator"}
CONTEXT_ORIGINS = {"ci", "bot", "third-party", "agent"}
LABELS = {ADMITTED: "ADMITIDO", APPLIED: "APLICADO", UNKNOWN: "NO SÉ", CONTEXT: "CONTEXTO"}
MAX_BUMP = 1000


# SE-513 S2 — niveles de promoción. Orden: LOCAL < COORDINACION < HUMANO.
LOCAL, COORD, HUMAN = "LOCAL", "COORDINACION", "HUMANO"
UNKNOWN_HUMAN_SEC = int(os.environ.get("TASK_QUEUE_UNKNOWN_HUMAN_SEC", "600"))
HUMAN_PRINCIPAL = "operator"


class AdmissionRefused(Exception):
    """La entrada no se admite y no deja rastro (exit 3 en la CLI)."""


def _crash_point(name: str) -> None:
    """Inyección de cortes para las pruebas de durabilidad (SE-513 AC-2).

    Solo actúa con SAVIA_TQ_TEST=1 además del punto de corte: una variable
    suelta en el entorno de un agente no tumba la cola.
    """
    if os.environ.get("SAVIA_TQ_TEST") == "1" and os.environ.get("SAVIA_TQ_CRASH_AT") == name:
        os._exit(137)


def _safe(text: Any) -> str:
    """Quita caracteres de control (ANSI/OSC, C1) y de formato (RLO, ancho cero) al mostrar."""
    return "".join("?" if unicodedata.category(c) in ("Cc", "Cf") else c for c in str(text))


def _hhmm(ts: float) -> str:
    return time.strftime("%H:%M", time.localtime(ts))


def _norm(text: str) -> str:
    return " ".join(text.lower().split())


def _proof_ok(row: sqlite3.Row, proof: Any) -> bool:
    """Prueba declarada por el harness: el plan del agente que RECIBIÓ el cambio lo cita (#seq).

    No es una firma. Exige que el cambio se haya entregado (`pull`) a un agente
    concreto (nunca al dueño provisional «cola») y que el harness tenga señal.
    """
    if row["delivered_at"] is None or row["owner"] in (None, "cola") or row["signal"] == "none":
        return False
    if not isinstance(proof, dict) or proof.get("owner") != row["owner"]:
        return False
    plan = proof.get("plan")
    if not isinstance(plan, list):
        return False
    pat = re.compile(rf"#{row['seq']}(?!\d)")
    return any(isinstance(step, str) and pat.search(step) for step in plan)


def _job_info(job: Any) -> dict | None:
    """Campos estructurados de un trabajo; None si la fila o su payload no son legibles."""
    try:
        status, worker, raw = job["status"], job["worker"], job["payload"]
        payload = json.loads(raw) if raw else {}
    except (KeyError, TypeError, IndexError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict):
        return None
    deps, acl = payload.get("depends_on"), payload.get("acl")
    if deps is not None and not (isinstance(deps, list) and all(isinstance(d, str) for d in deps)):
        return None
    if acl is not None and not (isinstance(acl, list) and all(isinstance(a, str) and a for a in acl)):
        return None
    principal = worker or payload.get("owner")
    return {"status": status, "deps": deps or [], "acl": acl,
            "principal": principal if isinstance(principal, str) and principal else None}


def promote(event: Any, jobs: dict[str, Any], now: float | None = None) -> dict:
    """Regla de promoción de un cambio admitido (SE-513 S2). Pura: no escribe nada.

    LOCAL        detalle del propio trabajo; no sale de su dueño.
    COORDINACION afecta a trabajos que dependen de él (depends_on) y cambia su orden/texto
                 o no hay prueba de aplicación; solo se avisa a quien figura en el `acl`
                 del trabajo afectado.
    HUMANO       necesita a la persona: efecto con permiso pendiente, UNKNOWN sin resolver
                 tras UNKNOWN_HUMAN_SEC, o coordinación necesaria sin nadie autorizado a recibirla.

    Solo se leen campos estructurados; el texto libre (p. ej. «URGENTE» de un tercero)
    no influye. Fail-closed: origen no autenticado, tipo no `change`, estado cerrado,
    trabajo ilegible/ausente/cerrado o `acl` ausente o mal formado → LOCAL, sin audiencia
    añadida.
    """
    def out(level: str, why: str, audience: list[str] | None = None, withheld: int = 0) -> dict:
        return {"level": level, "reason": why, "audience": sorted(set(audience or [])),
                "withheld": withheld}

    try:
        origin, kind, state = event["origin"], event["kind"], event["state"]
        job_id, created = event["job_id"], event["created_at"]
        bump, set_text = event["bump"], event["set_text"]
        eff_perm, owner = event["effect_permission"], event["owner"]
    except (KeyError, TypeError, IndexError):
        return out(LOCAL, "evento ilegible")
    if origin not in AUTH_ORIGINS or kind != "change":
        return out(LOCAL, "contexto: no es una orden autenticada")
    if state not in (ADMITTED, UNKNOWN):
        return out(LOCAL, "ya resuelto")
    if not isinstance(job_id, str) or not isinstance(jobs, dict) or job_id not in jobs:
        return out(LOCAL, "trabajo desconocido")
    info = _job_info(jobs[job_id])
    if info is None or info["status"] not in ("pending", "running"):
        return out(LOCAL, "trabajo ilegible o cerrado")
    now = time.time() if now is None else now
    if not isinstance(created, (int, float)) or isinstance(created, bool) or created > now:
        age = None
    else:
        age = now - created
    if eff_perm == "PENDING":
        return out(HUMAN, "efecto pendiente de permiso", [HUMAN_PRINCIPAL])
    if state == UNKNOWN and age is not None and age >= UNKNOWN_HUMAN_SEC:
        return out(HUMAN, "sin prueba de aplicación pasado el plazo", [HUMAN_PRINCIPAL])
    if not (bump or set_text is not None or state == UNKNOWN):
        return out(LOCAL, "sin efecto sobre otros trabajos")
    dependents = []
    for jid, j in jobs.items():
        ji = _job_info(j)
        if ji is not None and ji["status"] in ("pending", "running") and job_id in ji["deps"]:
            dependents.append(ji["principal"])
    if not any(dependents):
        return out(LOCAL, "nadie con dueño depende de este trabajo")
    if info["acl"] is None:
        return out(LOCAL, "sin acl: no se avisa a nadie más")
    allowed = set(info["acl"])
    targets = {p for p in dependents if p and p != owner}
    audience = sorted(targets & allowed)
    withheld = len(targets - allowed)
    if audience:
        return out(COORD, "otros trabajos dependen de este", audience, withheld)
    if targets or withheld:
        return out(HUMAN, "coordinación necesaria sin destinatario autorizado", [HUMAN_PRINCIPAL], withheld)
    return out(LOCAL, "los dependientes son del mismo dueño")


class TaskQueue:
    def __init__(self, name: str, queue_dir: Path = DEFAULT_QUEUE_DIR):
        self.name = name
        self.path = _queue_path(name, queue_dir)
        self._init_schema()
        self.recovered_on_open = self.recover()

    @contextmanager
    def _conn(self) -> Iterator[sqlite3.Connection]:
        conn = sqlite3.connect(str(self.path), timeout=10, isolation_level=None)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        try:
            yield conn
        finally:
            conn.close()

    def _init_schema(self) -> None:
        with self._conn() as conn:
            conn.executescript(_SCHEMA)
            # SE-513: prioridad para reordenar pendientes (migración en sitio).
            # Solo se toma el cerrojo de escritura si falta la columna.
            if "priority" in {r["name"] for r in conn.execute("PRAGMA table_info(jobs)")}:
                return
            conn.execute("BEGIN IMMEDIATE")
            cols = {r["name"] for r in conn.execute("PRAGMA table_info(jobs)")}
            if "priority" not in cols:
                conn.execute("ALTER TABLE jobs ADD COLUMN priority INTEGER NOT NULL DEFAULT 0")
            conn.execute("COMMIT")

    def enqueue(self, command: str, payload: Any | None = None) -> str:
        job_id = uuid.uuid4().hex
        now = time.time()
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO jobs (id, queue, command, payload, created_at) VALUES (?, ?, ?, ?, ?)",
                (job_id, self.name, command, json.dumps(payload) if payload is not None else None, now),
            )
        return job_id

    def dequeue(self, worker: str = "default") -> dict | None:
        """Atomically claim the oldest pending job for this worker."""
        now = time.time()
        with self._conn() as conn:
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute(
                "SELECT id, command, payload FROM jobs "
                "WHERE queue=? AND status='pending' ORDER BY priority DESC, created_at LIMIT 1",
                (self.name,),
            ).fetchone()
            if row is None:
                conn.execute("COMMIT")
                return None
            conn.execute(
                "UPDATE jobs SET status='running', worker=?, started_at=?, heartbeat=? WHERE id=?",
                (worker, now, now, row["id"]),
            )
            # SE-513: quien reclama el trabajo pasa a ser dueño de sus cambios abiertos
            # en la misma transacción. Así el cambio le llega aunque termine el trabajo
            # antes de hacer `pull`, y un dueño anterior que cayó deja de recibirlo.
            # Si ya se había entregado a otro, se marca como reentrega.
            conn.execute(
                "UPDATE admissions SET owner=?, delivered_at=NULL, "
                "recovered=CASE WHEN delivered_at IS NULL THEN recovered ELSE 1 END "
                "WHERE queue=? AND job_id=? AND kind='change' AND state IN (?,?) "
                "AND acked_at IS NULL AND owner IS NOT ?",
                (worker, self.name, row["id"], ADMITTED, UNKNOWN, worker),
            )
            conn.execute("COMMIT")
            return {"id": row["id"], "command": row["command"],
                    "payload": json.loads(row["payload"]) if row["payload"] else None}

    def heartbeat(self, job_id: str) -> None:
        with self._conn() as conn:
            conn.execute("UPDATE jobs SET heartbeat=? WHERE id=? AND status='running'", (time.time(), job_id))

    def complete(self, job_id: str, ok: bool = True, error: str | None = None) -> None:
        status = "done" if ok else "failed"
        now = time.time()
        with self._conn() as conn:
            conn.execute(
                "UPDATE jobs SET status=?, finished_at=?, error=? WHERE id=?",
                (status, now, error, job_id),
            )

    def status(self) -> dict:
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT status, COUNT(*) AS n FROM jobs WHERE queue=? GROUP BY status",
                (self.name,),
            ).fetchall()
        out: dict[str, int] = {"pending": 0, "running": 0, "done": 0, "failed": 0}
        for r in rows:
            out[r["status"]] = r["n"]
        return out

    def recover(self) -> int:
        """Reset stale running jobs (heartbeat older than STALE_HEARTBEAT_SEC) to pending.

        Auto-runs at TaskQueue() construction to recover from worker crashes.
        Returns the number of jobs recovered.
        """
        cutoff = time.time() - STALE_HEARTBEAT_SEC
        with self._conn() as conn:
            cursor = conn.execute(
                "UPDATE jobs SET status='pending', worker=NULL, started_at=NULL, heartbeat=NULL "
                "WHERE queue=? AND status='running' AND (heartbeat IS NULL OR heartbeat < ?)",
                (self.name, cutoff),
            )
            return cursor.rowcount

    def drain(self) -> int:
        """Delete all completed (done|failed) jobs. Returns number deleted."""
        with self._conn() as conn:
            cursor = conn.execute(
                "DELETE FROM jobs WHERE queue=? AND status IN ('done','failed')", (self.name,)
            )
            return cursor.rowcount

    # ── SE-513 S1: admisión duradera de cambios de intención ──────────────

    def admit(self, text: str, origin: str, kind: str = "change", job_id: str | None = None,
              bump: int = 0, set_text: str | None = None, signal: str = "plan",
              owner: str | None = None, key: str | None = None) -> dict:
        """Admite un cambio y aplica su salida a la cola en UNA transacción."""
        if origin not in AUTH_ORIGINS | CONTEXT_ORIGINS:
            raise ValueError(f"origen desconocido: {origin!r}")
        if not text.strip():
            raise ValueError("el texto del cambio está vacío")
        if kind not in ("change", "new_work") or signal not in ("plan", "none"):
            raise ValueError("kind o signal no válidos")
        if not isinstance(bump, int) or abs(bump) > MAX_BUMP:
            raise ValueError(f"--bump fuera de rango (±{MAX_BUMP})")
        if origin in AUTH_ORIGINS and kind == "new_work":
            raise AdmissionRefused("Abrir trabajo nuevo necesita un contrato; en esta fase "
                                   "solo se cambian el texto y el orden de trabajos pendientes.")
        eff_kind = "change" if origin in AUTH_ORIGINS else "context"
        if eff_kind == "change" and not job_id:
            raise AdmissionRefused("Falta el trabajo afectado (--job).")
        # Una clave explícita se mezcla con origen, tipo y trabajo: un origen no
        # autenticado no puede ocupar la clave de una orden del operador.
        ident = ["key", key] if key else [_norm(text), bump, set_text]
        dkey = hashlib.sha256(json.dumps(ident + [origin, kind, job_id]).encode()).hexdigest()
        now = time.time()
        with self._conn() as conn:
            conn.execute("BEGIN IMMEDIATE")
            prev = conn.execute("SELECT * FROM admissions WHERE queue=? AND dedup_key=?",
                                (self.name, dkey)).fetchone()
            if prev is not None:
                conn.execute("UPDATE admissions SET repeats=repeats+1, last_repeat_at=? "
                             "WHERE seq=?", (now, prev["seq"]))
                conn.execute("COMMIT")
                msg = f"Ya lo tenía anotado (a las {_hhmm(prev['created_at'])}). Lo trato como uno solo."
                if prev["state"] in (ADMITTED, UNKNOWN):
                    msg += " Sigue pendiente de que el agente llegue al final de su paso."
                return self._reply(prev, duplicate=True, message=msg)
            effect = None
            state = CONTEXT
            ignored = False
            if eff_kind == "change":
                job = conn.execute("SELECT status, worker, payload FROM jobs WHERE id=? AND queue=?",
                                   (job_id, self.name)).fetchone()
                if job is None or job["status"] not in ("pending", "running"):
                    conn.execute("ROLLBACK")
                    raise AdmissionRefused("El trabajo no está pendiente ni en curso.")
                try:
                    payload = json.loads(job["payload"]) if job["payload"] else {}
                except json.JSONDecodeError:
                    conn.execute("ROLLBACK")
                    raise ValueError("el payload del trabajo no es JSON legible")
                if set_text is not None and not isinstance(payload, dict):
                    conn.execute("ROLLBACK")
                    raise AdmissionRefused("Ese trabajo no tiene un texto que se pueda cambiar.")
                raw_effect = payload.get("effect") if isinstance(payload, dict) else None
                # Cualquier efecto declarado, sea del tipo que sea, sigue pidiendo permiso.
                effect = _safe(raw_effect) if raw_effect not in (None, "") else None
                owner = owner or job["worker"] or "cola"
                state = UNKNOWN if signal == "none" else ADMITTED
                if job["status"] == "pending":
                    if bump:
                        conn.execute("UPDATE jobs SET priority=priority+? WHERE id=?", (bump, job_id))
                    if set_text is not None:
                        payload["text"] = set_text
                        conn.execute("UPDATE jobs SET payload=? WHERE id=?",
                                     (json.dumps(payload), job_id))
                else:
                    # En curso: ni se reordena ni se cambia su texto; solo se avisa al agente.
                    ignored = bool(bump) or set_text is not None
            else:
                owner = None
            reason = "el agente no da señal de haberlo incorporado" if state == UNKNOWN else None
            cur = conn.execute(
                "INSERT INTO admissions (queue, dedup_key, text, origin, kind, state, owner, job_id, "
                "bump, set_text, signal, effect, effect_permission, reason, created_at) "
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                (self.name, dkey, text, origin, eff_kind, state, owner, job_id, bump, set_text,
                 signal, effect, "PENDING" if effect else None, reason, now))
            _crash_point("admit_before_commit")
            conn.execute("COMMIT")
            _crash_point("admit_after_commit")
            row = conn.execute("SELECT * FROM admissions WHERE seq=?", (cur.lastrowid,)).fetchone()
        if eff_kind == "context":
            msg = f"Guardado como contexto. Un mensaje de {origin} no abre trabajo ni cambia la cola."
        else:
            if ignored:
                lead = ("Anotado. Ese trabajo ya está en curso: no lo muevo en la cola ni "
                        "cambio su texto; se lo paso al agente al terminar su paso.")
            elif bump > 0:
                lead = "La adelanto en la cola."
            elif bump < 0:
                lead = "La retraso en la cola."
            else:
                lead = "Anotado."
            if effect:
                msg = f"{lead} {effect[:1].upper()}{effect[1:]} sigue necesitando tu permiso; no lo doy por concedido."
            elif state == UNKNOWN:
                msg = f"{lead} No sé si lo ha aplicado; lo confirmo cuando termine su paso."
            elif ignored:
                msg = lead
            else:
                msg = f"{lead} Lo verá al terminar su paso."
        return self._reply(row, duplicate=False, message=msg)

    @staticmethod
    def _reply(row: sqlite3.Row, duplicate: bool, message: str) -> dict:
        return {"id": row["seq"], "state": row["state"], "kind": row["kind"], "owner": row["owner"],
                "effect_permission": row["effect_permission"], "duplicate": duplicate,
                "message": message}

    def pull(self, owner: str) -> list[dict]:
        """Entrega al dueño sus cambios abiertos; reentrega lo entregado y no acusado tras un corte."""
        if not owner or owner == "cola":
            raise ValueError("pull necesita el nombre del agente; «cola» no es un agente")
        now = time.time()
        cutoff = now - STALE_HEARTBEAT_SEC
        with self._conn() as conn:
            conn.execute("BEGIN IMMEDIATE")
            # El cambio lo recibe su dueño. Un cambio sobre un trabajo pendiente nace
            # con dueño «cola» y `dequeue` lo pasa al agente que reclama el trabajo
            # (también tras reasignarlo porque el dueño anterior cayó), así que el
            # dueño es siempre quien tiene o tuvo el trabajo por última vez, y el
            # cambio se le entrega aunque el trabajo ya esté terminado.
            # Lo ya acusado (ack) no se reentrega.
            rows = conn.execute(
                "SELECT * FROM admissions "
                "WHERE queue=? AND kind='change' AND state IN (?,?) AND acked_at IS NULL "
                "AND owner=? AND (delivered_at IS NULL OR delivered_at < ?) "
                "ORDER BY seq",
                (self.name, ADMITTED, UNKNOWN, owner, cutoff)).fetchall()
            out = []
            for r in rows:
                again = 1 if (r["delivered_at"] is not None or r["recovered"]) else 0
                conn.execute("UPDATE admissions SET delivered_at=?, "
                             "recovered=MAX(recovered, ?) WHERE seq=?",
                             (now, again, r["seq"]))
                out.append({"id": r["seq"], "text": r["text"], "job_id": r["job_id"],
                            "state": r["state"], "recovered": again})
            conn.execute("COMMIT")
            _crash_point("pull_after_commit")
        return out

    def ack(self, seq: int, proof: Any | None = None) -> dict:
        """Cierre del paso del agente. APPLIED_TO_PLAN solo con prueba; si no, UNKNOWN."""
        with self._conn() as conn:
            conn.execute("BEGIN IMMEDIATE")
            row = conn.execute("SELECT * FROM admissions WHERE queue=? AND seq=?",
                               (self.name, seq)).fetchone()
            if row is None or row["kind"] != "change":
                conn.execute("ROLLBACK")
                raise AdmissionRefused(f"No hay ningún cambio admitido #{seq}.")
            if row["state"] == APPLIED:
                conn.execute("COMMIT")
                return self._reply(row, duplicate=True, message="Ya estaba aplicado.")
            new_state = APPLIED if _proof_ok(row, proof) else UNKNOWN
            now = time.time()
            conn.execute(
                "UPDATE admissions SET state=?, acked_at=?, applied_at=?, proof=?, reason=? "
                "WHERE seq=?",
                (new_state, now if row["delivered_at"] is not None else None,
                 now if new_state == APPLIED else None,
                 json.dumps(proof) if proof is not None else None,
                 None if new_state == APPLIED else "sin prueba de que el plan recoja el cambio",
                 seq))
            conn.execute("COMMIT")
            row = conn.execute("SELECT * FROM admissions WHERE seq=?", (seq,)).fetchone()
        if new_state == APPLIED:
            msg = f"Aplicado: {_safe(row['text'])}."
        else:
            msg = ("Ha terminado su paso. Sigue sin darme señal de su plan, así que no puedo "
                   "confirmarlo: el cambio sigue en NO SÉ.")
        return self._reply(row, duplicate=False, message=msg)

    def changes(self, include_all: bool = False) -> list[dict]:
        with self._conn() as conn:
            if include_all:
                rows = conn.execute("SELECT * FROM admissions WHERE queue=? ORDER BY seq",
                                    (self.name,)).fetchall()
            else:
                rows = conn.execute("SELECT * FROM admissions WHERE queue=? AND state IN (?,?) "
                                    "ORDER BY seq", (self.name, ADMITTED, UNKNOWN)).fetchall()
        return [dict(r) for r in rows]

    def promotions(self, now: float | None = None) -> list[dict]:
        """Nivel de promoción de cada cambio abierto. Solo lectura sobre la misma cola."""
        with self._conn() as conn:
            jobs = {r["id"]: dict(r) for r in conn.execute(
                "SELECT id, status, worker, payload FROM jobs WHERE queue=?", (self.name,))}
        out = []
        for c in self.changes():
            res = promote(c, jobs, now)
            res["id"] = c["seq"]
            out.append(res)
        return out

    def list_jobs(self, status: str | None = None, limit: int = 50) -> list[dict]:
        with self._conn() as conn:
            if status:
                rows = conn.execute(
                    "SELECT * FROM jobs WHERE queue=? AND status=? ORDER BY created_at LIMIT ?",
                    (self.name, status, limit),
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM jobs WHERE queue=? ORDER BY created_at LIMIT ?",
                    (self.name, limit),
                ).fetchall()
        return [dict(r) for r in rows]


def _cli() -> int:
    p = argparse.ArgumentParser(prog="task-queue.py")
    sp = p.add_subparsers(dest="cmd", required=True)

    e = sp.add_parser("enqueue"); e.add_argument("queue"); e.add_argument("command")
    e.add_argument("--payload", default=None)

    d = sp.add_parser("dequeue"); d.add_argument("queue"); d.add_argument("--worker", default="default")

    c = sp.add_parser("complete"); c.add_argument("queue"); c.add_argument("job_id")
    g = c.add_mutually_exclusive_group(required=True)
    g.add_argument("--ok", action="store_true")
    g.add_argument("--fail", metavar="MSG")

    s = sp.add_parser("status"); s.add_argument("queue"); s.add_argument("--json", action="store_true")
    r = sp.add_parser("recover"); r.add_argument("queue")
    dr = sp.add_parser("drain"); dr.add_argument("queue")
    li = sp.add_parser("list"); li.add_argument("queue"); li.add_argument("--status", default=None)
    li.add_argument("--limit", type=int, default=50)

    ad = sp.add_parser("admit"); ad.add_argument("queue"); ad.add_argument("--text", required=True)
    ad.add_argument("--origin", required=True,
                    choices=sorted(AUTH_ORIGINS | CONTEXT_ORIGINS))
    ad.add_argument("--kind", default="change", choices=["change", "new_work"])
    ad.add_argument("--job", default=None); ad.add_argument("--bump", type=int, default=0)
    ad.add_argument("--set-text", default=None); ad.add_argument("--owner", default=None)
    ad.add_argument("--signal", default="plan", choices=["plan", "none"])
    ad.add_argument("--key", default=None)
    pr = sp.add_parser("promote"); pr.add_argument("queue"); pr.add_argument("--json", action="store_true")
    pu = sp.add_parser("pull"); pu.add_argument("queue"); pu.add_argument("--owner", required=True)
    ak = sp.add_parser("ack"); ak.add_argument("queue"); ak.add_argument("id", type=int)
    ak.add_argument("--plan-proof", default=None)
    ch = sp.add_parser("changes"); ch.add_argument("queue")
    ch.add_argument("--all", action="store_true"); ch.add_argument("--json", action="store_true")

    args = p.parse_args()
    try:
        q = TaskQueue(args.queue)
    except ValueError as ex:
        print(f"ERROR: {ex}", file=sys.stderr); return 2

    if args.cmd == "enqueue":
        payload = json.loads(args.payload) if args.payload else None
        print(q.enqueue(args.command, payload))
    elif args.cmd == "dequeue":
        job = q.dequeue(args.worker)
        if job is None: return 1
        print(json.dumps(job))
    elif args.cmd == "complete":
        if args.ok: q.complete(args.job_id, ok=True)
        else: q.complete(args.job_id, ok=False, error=args.fail)
        print("ok")
    elif args.cmd == "status":
        st = q.status()
        if args.json: print(json.dumps(st))
        else:
            for k, v in st.items(): print(f"  {k}: {v}")
    elif args.cmd == "recover":
        n = q.recover()
        print(f"recovered={n}")
        open_changes = q.changes()
        # Solo se habla de reinicio si de verdad había trabajos en curso abandonados.
        if open_changes and (n + q.recovered_on_open) > 0:
            print("Hemos tenido un reinicio.")
        for c in open_changes:
            print(f"Tu cambio de las {_hhmm(c['created_at'])} sigue en la cola; no hace falta "
                  f"repetirlo. (#{c['seq']} {_safe(c['text'])}, {LABELS[c['state']]})")
    elif args.cmd in ("admit", "ack"):
        try:
            if args.cmd == "admit":
                res = q.admit(args.text, args.origin, kind=args.kind, job_id=args.job,
                              bump=args.bump, set_text=args.set_text, signal=args.signal,
                              owner=args.owner, key=args.key)
            else:
                try:
                    proof = json.loads(args.plan_proof) if args.plan_proof else None
                except json.JSONDecodeError:
                    print("ERROR: --plan-proof no es JSON válido", file=sys.stderr); return 2
                res = q.ack(args.id, proof)
        except AdmissionRefused as ex:
            print(f"RECHAZADO: {ex}", file=sys.stderr); return 3
        except ValueError as ex:
            print(f"ERROR: {ex}", file=sys.stderr); return 2
        print(json.dumps(res, ensure_ascii=False))
    elif args.cmd == "pull":
        try:
            print(json.dumps(q.pull(args.owner), ensure_ascii=False))
        except ValueError as ex:
            print(f"ERROR: {ex}", file=sys.stderr); return 2
    elif args.cmd == "promote":
        rows = q.promotions()
        if args.json:
            print(json.dumps(rows, ensure_ascii=False)); return 0
        for r in rows:
            aud = ",".join(r["audience"]) or "-"
            print(f"#{r['id']:<6} {r['level']:<13} audiencia={aud} ({r['reason']})")
    elif args.cmd == "changes":
        rows = q.changes(args.all)
        if args.json:
            print(json.dumps(rows, ensure_ascii=False, default=str)); return 0
        print(f"{'cambio':<7} {'texto':<40} {'estado':<10} {'desde':<6} notas")
        for c in rows:
            notes = []
            if c["repeats"]:
                notes.append(f"repetido {c['repeats']} vez, no cuenta como otro")
            if c["recovered"]:
                notes.append("reentregado: no acusó la entrega anterior")
            if c["effect_permission"]:
                notes.append(f"permiso para {_safe(c['effect'])}: PENDIENTE")
            if c["reason"]:
                notes.append(c["reason"])
            print(f"#{c['seq']:<6} {_safe(c['text'])[:40]:<40} {LABELS[c['state']]:<10} "
                  f"{_hhmm(c['created_at']):<6} {'; '.join(notes)}")
    elif args.cmd == "drain":
        print(f"deleted={q.drain()}")
    elif args.cmd == "list":
        for row in q.list_jobs(args.status, args.limit):
            print(json.dumps(row, default=str))
    return 0


if __name__ == "__main__":
    sys.exit(_cli())
