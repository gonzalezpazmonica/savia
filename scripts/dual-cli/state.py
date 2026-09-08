"""Durable coordination primitives. Leases never expire automatically.

release is an internal primitive: a future process supervisor must verify that
all writers have finished before invoking it. It is not exposed over a socket.
"""
from contextlib import contextmanager
import hashlib
import json
import os
from pathlib import Path
import secrets
import sqlite3

from protocol import ProtocolError, canonical, identifier


class Store:
    def __init__(self, path, repo_id):
        self.path = Path(path)
        self.repo_id = identifier(repo_id)
        # Caller owns the private parent directory. Do not follow database links.
        fd = os.open(self.path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
        try:
            if os.fstat(fd).st_uid != os.getuid():
                raise ProtocolError("UNTRUSTED")
            os.fchmod(fd, 0o600)
        finally:
            os.close(fd)
        with self.connection() as db:
            db.execute("CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT)")
            db.execute("CREATE TABLE IF NOT EXISTS consumers (session TEXT PRIMARY KEY, revision TEXT)")
            db.execute("CREATE TABLE IF NOT EXISTS lease (slot INTEGER PRIMARY KEY CHECK(slot=1), session TEXT, call TEXT, token TEXT)")
            columns = {row[1] for row in db.execute("PRAGMA table_info(lease)")}
            if "event_id" not in columns:
                db.execute("ALTER TABLE lease ADD COLUMN event_id TEXT")
            if "digest" not in columns:
                db.execute("ALTER TABLE lease ADD COLUMN digest TEXT")
            db.execute("CREATE TABLE IF NOT EXISTS completed (session TEXT, call TEXT, PRIMARY KEY(session, call))")
            db.execute("CREATE TABLE IF NOT EXISTS journal (sequence INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT UNIQUE, digest TEXT, decision TEXT)")
            db.execute("INSERT OR IGNORE INTO meta VALUES ('repo', ?)", (self.repo_id,))
            if db.execute("SELECT value FROM meta WHERE key='repo'").fetchone()[0] != self.repo_id:
                raise ProtocolError("CONFLICT")

    @contextmanager
    def connection(self):
        db = sqlite3.connect(self.path, timeout=10, isolation_level=None)
        try:
            db.execute("PRAGMA synchronous=FULL")
            db.execute("BEGIN IMMEDIATE")
            yield db
            db.execute("COMMIT")
        except BaseException:
            if db.in_transaction:
                db.execute("ROLLBACK")
            raise
        finally:
            db.close()

    @staticmethod
    def revision(db):
        row = db.execute("SELECT value FROM meta WHERE key='revision'").fetchone()
        return row[0] if row else None

    def publish(self, revision, *, expected):
        identifier(revision)
        with self.connection() as db:
            if self.revision(db) != expected:
                raise ProtocolError("CONFLICT")
            if db.execute("SELECT 1 FROM lease").fetchone():
                raise ProtocolError("CONFLICT")
            db.execute("INSERT OR REPLACE INTO meta VALUES ('revision', ?)", (revision,))

    def hello(self, session):
        identifier(session)
        with self.connection() as db:
            db.execute("INSERT OR REPLACE INTO consumers VALUES (?, NULL)", (session,))
            return self.revision(db)

    def ack(self, session, revision):
        with self.connection() as db:
            if not revision or self.revision(db) != revision:
                raise ProtocolError("STALE_REVISION")
            if not db.execute("UPDATE consumers SET revision=? WHERE session=?", (revision, session)).rowcount:
                raise ProtocolError("UNTRUSTED")

    def acquire(self, session, revision, call):
        identifier(call)
        with self.connection() as db:
            consumer = db.execute("SELECT revision FROM consumers WHERE session=?", (session,)).fetchone()
            if not consumer:
                raise ProtocolError("UNTRUSTED")
            if not revision or self.revision(db) != revision or consumer[0] != revision:
                raise ProtocolError("STALE_REVISION")
            if db.execute("SELECT 1 FROM completed WHERE session=? AND call=?", (session, call)).fetchone():
                raise ProtocolError("CONFLICT")
            held = db.execute("SELECT session, call, token FROM lease").fetchone()
            if held:
                if held[:2] == (session, call):
                    return held[2]
                raise ProtocolError("CONFLICT")
            token = secrets.token_hex(32)
            db.execute(
                "INSERT INTO lease(slot, session, call, token) VALUES (1, ?, ?, ?)",
                (session, call, token),
            )
            return token

    def release(self, session, token):
        with self.connection() as db:
            held = db.execute("SELECT call FROM lease WHERE session=? AND token=?", (session, token)).fetchone()
            if not held:
                raise ProtocolError("CONFLICT")
            db.execute("INSERT INTO completed VALUES (?, ?)", (session, held[0]))
            db.execute("DELETE FROM lease WHERE session=? AND token=?", (session, token))

    def admit(self, event, session, revision, call):
        """Atomically replay a committed event or reserve a new execution.

        A matching live reservation is deliberately not reusable: execution may
        already have produced an external effect, so only explicit reconciliation
        may clear it.
        """
        identifier(call)
        if event["repo_id"] != self.repo_id:
            raise ProtocolError("UNTRUSTED")
        digest = hashlib.sha256(canonical(event).encode()).hexdigest()
        with self.connection() as db:
            consumer = db.execute(
                "SELECT revision FROM consumers WHERE session=?", (session,)
            ).fetchone()
            if not consumer:
                raise ProtocolError("UNTRUSTED")
            if not revision or self.revision(db) != revision or consumer[0] != revision:
                raise ProtocolError("STALE_REVISION")
            old = db.execute(
                "SELECT sequence, digest, decision FROM journal WHERE event_id=?",
                (event["event_id"],),
            ).fetchone()
            if old:
                if old[1] != digest:
                    raise ProtocolError("CONFLICT")
                return None, (old[0], json.loads(old[2]))
            held = db.execute(
                "SELECT session, call, event_id, digest FROM lease"
            ).fetchone()
            if held:
                if held[2] == event["event_id"] and held[3] not in (None, digest):
                    raise ProtocolError("CONFLICT")
                raise ProtocolError("AMBIGUOUS_EXECUTION")
            if db.execute(
                "SELECT 1 FROM completed WHERE session=? AND call=?", (session, call)
            ).fetchone():
                raise ProtocolError("CONFLICT")
            token = secrets.token_hex(32)
            db.execute(
                "INSERT INTO lease(slot, session, call, token, event_id, digest) "
                "VALUES (1, ?, ?, ?, ?, ?)",
                (session, call, token, event["event_id"], digest),
            )
            return token, None

    def complete(self, event, decision, session, token):
        """Commit the decision and release its reservation atomically."""
        if event["repo_id"] != self.repo_id:
            raise ProtocolError("UNTRUSTED")
        digest = hashlib.sha256(canonical(event).encode()).hexdigest()
        serialized = canonical(decision)
        with self.connection() as db:
            held = db.execute(
                "SELECT call, event_id, digest FROM lease "
                "WHERE session=? AND token=?", (session, token)
            ).fetchone()
            if not held or held[1:] != (event["event_id"], digest):
                raise ProtocolError("CONFLICT")
            old = db.execute(
                "SELECT sequence, digest, decision FROM journal WHERE event_id=?",
                (event["event_id"],),
            ).fetchone()
            if old:
                if old[1:] != (digest, serialized):
                    raise ProtocolError("CONFLICT")
                sequence = old[0]
            else:
                sequence = db.execute(
                    "INSERT INTO journal(event_id, digest, decision) VALUES (?, ?, ?)",
                    (event["event_id"], digest, serialized),
                ).lastrowid
            db.execute("INSERT INTO completed VALUES (?, ?)", (session, held[0]))
            db.execute("DELETE FROM lease WHERE session=? AND token=?", (session, token))
            return sequence

    def prior_record(self, event):
        """Return a previously committed decision for an identical event."""
        if event["repo_id"] != self.repo_id:
            raise ProtocolError("UNTRUSTED")
        digest = hashlib.sha256(canonical(event).encode()).hexdigest()
        with self.connection() as db:
            row = db.execute("SELECT sequence, digest, decision FROM journal WHERE event_id=?",
                             (event["event_id"],)).fetchone()
            if not row:
                return None
            if row[1] != digest:
                raise ProtocolError("CONFLICT")
            return row[0], json.loads(row[2])

    def close_session(self, session):
        with self.connection() as db:
            if db.execute("SELECT 1 FROM lease WHERE session=?", (session,)).fetchone():
                raise ProtocolError("CONFLICT")
            db.execute("DELETE FROM consumers WHERE session=?", (session,))

    def record(self, event, decision):
        if event["repo_id"] != self.repo_id:
            raise ProtocolError("UNTRUSTED")
        digest = hashlib.sha256(canonical(event).encode()).hexdigest()
        serialized = canonical(decision)
        with self.connection() as db:
            old = db.execute("SELECT sequence, digest, decision FROM journal WHERE event_id=?", (event["event_id"],)).fetchone()
            if old:
                if old[1:] != (digest, serialized):
                    raise ProtocolError("CONFLICT")
                return old[0]
            return db.execute("INSERT INTO journal(event_id, digest, decision) VALUES (?, ?, ?)",
                              (event["event_id"], digest, serialized)).lastrowid

    def status(self):
        with self.connection() as db:
            return {"revision": self.revision(db),
                    "sequence": db.execute("SELECT coalesce(max(sequence), 0) FROM journal").fetchone()[0],
                    "consumers": [{"session_id": s, "revision": r} for s, r in db.execute("SELECT session, revision FROM consumers ORDER BY session")],
                    "reservations": db.execute("SELECT count(*) FROM lease").fetchone()[0],
                    "certified": False}
