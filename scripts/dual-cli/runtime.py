"""Experimental Unix control plane; execution adapters are NOT enabled."""
import argparse
import asyncio
import hmac
import fcntl
import os
from pathlib import Path
import secrets
import socket
import stat
import struct
from protocol import MAX_BYTES, ProtocolError, canonical, decode_event, decode_json, identifier
from state import Store
from contracts import execution_request, execution_result, AdapterRegistry


class Runtime:
    def __init__(self, store, adapters=()):
        self.store = store
        self.sessions = {}
        self.adapters = AdapterRegistry(adapters)

    def handle(self, request):
        if not isinstance(request, dict):
            raise ProtocolError("INVALID_EVENT")
        operation = request.get("op")
        fields = {"status": {"op"}, "hello": {"op", "session_id"},
                  "ack": {"op", "session_id", "session_token", "revision"},
                  "close": {"op", "session_id", "session_token"},
                  "dispatch": {"op", "session_id", "session_token", "event"}}
        if not isinstance(operation, str) or operation not in fields:
            raise ProtocolError("UNSUPPORTED_CAPABILITY")
        if set(request) != fields[operation]:
            raise ProtocolError("INVALID_EVENT")
        if operation == "status":
            result = self.store.status()
            result["gaps"] = ["EXECUTION_ADAPTERS_UNIMPLEMENTED", "PROCESS_SUPERVISOR_UNIMPLEMENTED"]
            return result
        session = identifier(request["session_id"])
        if operation == "hello":
            if session in self.sessions:
                raise ProtocolError("CONFLICT")
            revision = self.store.hello(session)
            self.sessions[session] = secrets.token_hex(32)
            return {"revision": revision, "session_token": self.sessions[session], "certified": False}
        token = request.get("session_token")
        if (not isinstance(token, str) or session not in self.sessions
                or not hmac.compare_digest(token, self.sessions[session])):
            raise ProtocolError("UNTRUSTED")
        if operation == "ack":
            self.store.ack(session, identifier(request["revision"]))
            return {"ok": True}
        if operation == "close":
            self.store.close_session(session)
            del self.sessions[session]
            return {"ok": True}
        event = decode_event(canonical(request["event"]).encode())
        if event["session_id"] != session or event["repo_id"] != self.store.repo_id:
            raise ProtocolError("UNTRUSTED")
        status = self.store.status()
        consumer = next(c for c in status["consumers"] if c["session_id"] == session)
        if event["revision"] != status["revision"] or consumer["revision"] != status["revision"]:
            raise ProtocolError("STALE_REVISION")
        prior = self.store.prior_record(event)
        if prior is not None:
            sequence, decision = prior
            decision["sequence"] = sequence
            return decision
        payload = event.get("payload")
        if isinstance(payload, dict) and payload.get("schema") == 2:
            adapter = self.adapters.get(payload.get("adapter_id"))
            request = execution_request(payload.get("request"))
            if request["external_effect_intent"]:
                raise ProtocolError("EXTERNAL_EFFECT")
            context = {"request_id": request["request_id"], "capability_id": request["capability_id"]}
            if adapter.preflight(context).get("ok") is not True:
                raise ProtocolError("UNSUPPORTED_CAPABILITY")
            lease, replay = self.store.admit(
                event, session, event["revision"], event["call_id"]
            )
            if replay is not None:
                sequence, decision = replay
                decision["sequence"] = sequence
                return decision
            result = execution_result(adapter.execute(request))
            if result["request_id"] != request["request_id"]:
                raise ProtocolError("INCONSISTENT_RESULT")
            result["sequence"] = self.store.complete(event, result, session, lease)
            return result
        result = {"action": "deny", "reason": "UNSUPPORTED_CAPABILITY",
                  "revision": status["revision"], "context": None,
                  "updated_input": None, "lease": None}
        result["sequence"] = self.store.record(event, result)
        return result

    async def client(self, reader, writer):
        try:
            peer = writer.get_extra_info("socket")
            _, uid, _ = struct.unpack("3i", peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
            if uid != os.getuid():
                raise ProtocolError("UNTRUSTED")
            raw = await asyncio.wait_for(reader.readline(), timeout=5)
            if not raw.endswith(b"\n"):
                raise ProtocolError("INVALID_EVENT")
            result = self.handle(decode_json(raw))
        except ProtocolError as error:
            result = {"action": "deny", "error": error.code}
        except (ValueError, UnicodeError, asyncio.TimeoutError):
            result = {"action": "deny", "error": "INVALID_EVENT"}
        except Exception:
            result = {"action": "deny", "error": "UNAVAILABLE"}
        try:
            writer.write(canonical(result).encode() + b"\n")
            await asyncio.wait_for(writer.drain(), timeout=5)
        finally:
            writer.close()
            await writer.wait_closed()


async def serve(folder, repo_id, revision):
    folder = Path(folder)
    folder.mkdir(mode=0o700, parents=True, exist_ok=True)
    metadata = folder.lstat()
    if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_uid != os.getuid()
            or metadata.st_mode & 0o077):
        raise ProtocolError("UNTRUSTED")
    # Hold the advisory lock for this coroutine lifetime, including cancellation.
    lock_fd = os.open(folder / "runtime.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        await serve_locked(folder, repo_id, revision)
    finally:
        os.close(lock_fd)


def remove_stale_socket(path):
    try:
        before = path.lstat()
    except FileNotFoundError:
        return
    if (not stat.S_ISSOCK(before.st_mode) or before.st_uid != os.getuid()
            or before.st_mode & 0o077):
        raise ProtocolError("UNTRUSTED")
    probe = socket.socket(socket.AF_UNIX)
    try:
        probe.settimeout(.2)
        probe.connect(str(path))
    except (ConnectionRefusedError, FileNotFoundError):
        pass
    else:
        raise ProtocolError("CONFLICT")
    finally:
        probe.close()
    after = path.lstat()
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        raise ProtocolError("CONFLICT")
    path.unlink()


async def serve_locked(folder, repo_id, revision):
    path = folder / "runtime.sock"
    remove_stale_socket(path)
    store = Store(folder / "state.db", repo_id)
    current = store.status()["revision"]
    if current is None:
        store.publish(revision, expected=None)
    elif current != revision:
        raise ProtocolError("STALE_REVISION")
    runtime = Runtime(store)
    server = await asyncio.start_unix_server(runtime.client, str(path), limit=MAX_BYTES)
    os.chmod(path, 0o600)
    owned = path.lstat()
    try:
        async with server:
            await server.serve_forever()
    finally:
        try:
            current = path.lstat()
            if (current.st_dev, current.st_ino) == (owned.st_dev, owned.st_ino):
                path.unlink()
        except FileNotFoundError:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, required=True)
    parser.add_argument("--repo-id", required=True)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        asyncio.run(serve(args.state_dir, identifier(args.repo_id), identifier(args.revision)))
    except (OSError, ProtocolError):
        print('{"action":"deny","error":"UNAVAILABLE"}')
        return 2
    except KeyboardInterrupt:
        return 0


if __name__ == "__main__":
    raise SystemExit(main())
