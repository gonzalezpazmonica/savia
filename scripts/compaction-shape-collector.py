#!/usr/bin/env python3
"""SE-529 S0.1 — colector de forma de las cargas de compactación.

Opt-in: solo actúa con SAVIA_COMPACT_SHAPE=1. No se registra en settings.json.
Registra FORMA y LONGITUDES, nunca texto: nombres de campo (solo si parecen
identificadores), tipo, bytes, y para el transcript: existencia, base de la ruta
(sin la ruta), recuentos por tipo de línea y tamaños. Siempre sale 0 y no imprime
nada, para no alterar ni el contexto del modelo ni la compactación.

Uso: compaction-shape-collector.py --event PreCompact|PostCompact|SessionStart
     --frontend claude-code|opencode   (carga JSON por stdin)
"""
import argparse, json, os, re, sys, time

EVENTS = {"PreCompact", "PostCompact", "SessionStart", "experimental.session.compacting",
          "session.compacted", "experimental.compaction.autocontinue"}
FRONTENDS = {"claude-code", "opencode"}
KEY_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_.:-]{0,39}$")
ENUM_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")
MAX_STDIN = 4 * 1024 * 1024
MAX_DEPTH = 6
MAX_KEYS = 64


def blen(s):
    return len(s.encode("utf-8", "replace"))


def key_name(k):
    return k if isinstance(k, str) and KEY_RE.match(k) else "<key>"


def shape(v, depth=0):
    if isinstance(v, bool):
        return {"t": "bool"}
    if v is None:
        return {"t": "null"}
    if isinstance(v, (int, float)):
        return {"t": "number"}
    if isinstance(v, str):
        return {"t": "str", "bytes": blen(v)}
    if depth >= MAX_DEPTH:
        return {"t": "deep"}
    if isinstance(v, list):
        kinds = sorted({shape(x, depth + 1)["t"] for x in v[:50]})
        return {"t": "list", "n": len(v), "item_types": kinds}
    if isinstance(v, dict):
        keys = {}
        for i, (k, x) in enumerate(v.items()):
            if i >= MAX_KEYS:
                break
            keys[key_name(k)] = shape(x, depth + 1)
        return {"t": "object", "n": len(v), "keys": keys}
    return {"t": "other"}


def enum(v):
    return v if isinstance(v, str) and ENUM_RE.match(v) else "other"


def pctl(vals, p):
    if not vals:
        return 0
    s = sorted(vals)
    return s[min(len(s) - 1, int(round(p * (len(s) - 1))))]


def data_dirs():
    home = os.path.expanduser("~")
    return [os.path.realpath(os.path.join(home, ".claude", "projects")),
            os.path.realpath(os.path.join(home, ".local", "share", "opencode")),
            os.path.realpath(os.path.join(home, ".local", "state", "opencode"))]


def analyze_transcript(path):
    t = {"present": True, "exists": False, "regular": False, "symlink": False,
         "base": "other"}
    try:
        t["symlink"] = os.path.islink(path)
        real = os.path.realpath(path)
        for d in data_dirs():
            if real == d or real.startswith(d + os.sep):
                t["base"] = "frontend_data_dir"
        if t["base"] == "other" and not os.path.exists(path):
            # ausente y fuera de la base conocida: se clasifica por el texto de la ruta
            ap = os.path.abspath(path)
            if any(ap.startswith(d + os.sep) for d in data_dirs()):
                t["base"] = "frontend_data_dir"
        if not os.path.exists(path):
            return t
        t["exists"] = True
        t["regular"] = os.path.isfile(path)
        st = os.stat(path)
        t["size_bytes"] = st.st_size
        t["owned_by_user"] = st.st_uid == os.getuid()
        if not t["regular"] or t["base"] != "frontend_data_dir":
            return t
        cap = int(os.environ.get("SAVIA_COMPACT_SHAPE_MAX_READ", str(32 * 1024 * 1024)))
        with open(path, "rb") as f:
            if st.st_size > cap:
                f.seek(st.st_size - cap)
                f.readline()  # descarta la línea parcial
                t["truncated"] = True
            else:
                t["truncated"] = False
            data = f.read(cap)
        t["bytes_read"] = len(data)
        lines = data.split(b"\n")
        if lines and lines[-1] == b"":
            lines.pop()
        types, blocks, topkeys = {}, {}, {}
        sizes, turn_sizes = [], []
        json_n = non_json = 0
        boundary = summary = False
        for ln in lines:
            sizes.append(len(ln))
            try:
                o = json.loads(ln)
            except Exception:
                non_json += 1
                continue
            if not isinstance(o, dict):
                non_json += 1
                continue
            json_n += 1
            ty = enum(o.get("type"))
            sub = o.get("subtype")
            key = ty + (":" + enum(sub) if isinstance(sub, str) else "")
            types[key] = types.get(key, 0) + 1
            for k in o:
                kk = key_name(k)
                topkeys[kk] = topkeys.get(kk, 0) + 1
            if key == "system:compact_boundary":
                boundary = True
            if o.get("isCompactSummary") is True:
                summary = True
            if ty in ("user", "assistant"):
                turn_sizes.append(len(ln))
            msg = o.get("message")
            c = msg.get("content") if isinstance(msg, dict) else None
            if isinstance(c, list):
                for b in c:
                    if isinstance(b, dict):
                        bt = enum(b.get("type"))
                        blocks[bt] = blocks.get(bt, 0) + 1
            elif isinstance(c, str):
                blocks["string"] = blocks.get("string", 0) + 1
        t.update({"line_count": len(lines), "json_lines": json_n,
                  "non_json_lines": non_json, "line_types": types,
                  "block_types": blocks, "top_level_keys": topkeys,
                  "p50_line_bytes": pctl(sizes, 0.5), "p90_line_bytes": pctl(sizes, 0.9),
                  "max_line_bytes": max(sizes) if sizes else 0,
                  "last30_turn_bytes": sum(turn_sizes[-30:]),
                  "has_compact_boundary": boundary, "has_compact_summary_line": summary})
    except Exception as e:  # nunca romper la compactación
        t["error"] = type(e).__name__
    return t


def main():
    if os.environ.get("SAVIA_COMPACT_SHAPE") != "1":
        return
    ap = argparse.ArgumentParser(add_help=False)
    ap.add_argument("--event", default="")
    ap.add_argument("--frontend", default="")
    a, _ = ap.parse_known_args()
    raw = sys.stdin.buffer.read(MAX_STDIN + 1)
    rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "event": a.event if a.event in EVENTS else "other",
           "frontend": a.frontend if a.frontend in FRONTENDS else "other",
           "stdin_bytes": min(len(raw), MAX_STDIN), "stdin_truncated": len(raw) > MAX_STDIN}
    try:
        obj = json.loads(raw[:MAX_STDIN].decode("utf-8"))
        rec["parse_error"] = False
        rec["payload"] = shape(obj)
        tp = obj.get("transcript_path") if isinstance(obj, dict) else None
        if isinstance(tp, str) and tp:
            rec["transcript"] = analyze_transcript(tp)
        else:
            rec["transcript"] = {"present": False}
    except Exception:
        rec["parse_error"] = True
    log = os.environ.get("SAVIA_COMPACT_SHAPE_LOG") or os.path.join(
        os.path.expanduser("~"), ".local", "state", "savia", "compact-shape.jsonl")
    d = os.path.dirname(log)
    os.makedirs(d, mode=0o700, exist_ok=True)
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
    with os.fdopen(fd, "a") as f:
        f.write(json.dumps(rec, sort_keys=True) + "\n")


if __name__ == "__main__":
    try:
        main()
    except BaseException:
        pass
    sys.exit(0)
