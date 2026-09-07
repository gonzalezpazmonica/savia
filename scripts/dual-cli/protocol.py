"""Strict, bounded protocol v1 decoding; no execution during validation."""
import json
import math

MAX_BYTES = 1024 * 1024


class ProtocolError(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


def _pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ProtocolError("INVALID_EVENT")
        result[key] = value
    return result


def _constant(value):
    raise ProtocolError("INVALID_EVENT")


def _float(value):
    number = float(value)
    if not math.isfinite(number):
        raise ProtocolError("INVALID_EVENT")
    return number


def decode_json(raw):
    if not isinstance(raw, bytes) or len(raw) > MAX_BYTES:
        raise ProtocolError("INVALID_EVENT")
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_pairs,
                          parse_constant=_constant, parse_float=_float)
    except (ValueError, UnicodeError, RecursionError):
        raise ProtocolError("INVALID_EVENT") from None


def identifier(value):
    if (not isinstance(value, str) or not value or len(value) > 256
            or any(ord(c) < 32 or 0xD800 <= ord(c) <= 0xDFFF for c in value)):
        raise ProtocolError("INVALID_EVENT")
    return value


def decode_event(raw):
    value = decode_json(raw)
    fields = {"version", "repo_id", "frontend", "session_id", "actor_id",
              "event_id", "call_id", "kind", "revision", "payload"}
    if not isinstance(value, dict) or set(value) != fields:
        raise ProtocolError("INVALID_EVENT")
    if type(value["version"]) is not int or value["version"] != 1:
        raise ProtocolError("INVALID_EVENT")
    if value["frontend"] not in ("codex", "opencode"):
        raise ProtocolError("INVALID_EVENT")
    for key in fields - {"version", "payload", "call_id"}:
        identifier(value[key])
    if value["call_id"] is not None:
        identifier(value["call_id"])
    return value


def canonical(value):
    try:
        return json.dumps(value, sort_keys=True, separators=(",", ":"), allow_nan=False)
    except (ValueError, TypeError, RecursionError):
        raise ProtocolError("INVALID_EVENT") from None
