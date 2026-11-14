#!/usr/bin/env python3
"""SE-529 S4 — guarda el resumen compactado una sola vez y dice la verdad del resultado.

Entrada: la carga JSON del evento PostCompact por stdin. Salida: UNA línea de estado
(o nada si la entrada está vacía). Siempre sale 0: un hook de compactación no bloquea.

Estados (el aviso solo dice «guardado» cuando está confirmado):
  confirmado     el resumen está en el almacén (recién guardado, o ya estaba).
  fallido        el intento de guardar devolvió error.
  desconocido    el guardado no dio error pero la entrada no aparece al releer.
  no disponible  la carga no trae el resumen (p. ej. OpenCode) o falta la sesión.

Clave de idempotencia: topic compact-summary/<sesión>/<sha256 del resumen normalizado>.
Misma clave ya guardada: no escribe. El contenido pasa por redact_private (S5) dentro de
`memory-store.sh save`. Límite heredado: `save` recorta el contenido a 2000 caracteres.
"""
import hashlib
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_PAYLOAD = 4 * 1024 * 1024
LABEL = "Resumen compactado"


def normalize(text):
    return " ".join(text.split())


def session_of(payload):
    for path in (("session_id",), ("properties", "sessionID"), ("input", "sessionID")):
        cur = payload
        for k in path:
            cur = cur.get(k) if isinstance(cur, dict) else None
        if isinstance(cur, str) and re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", cur):
            return cur
    return ""


def store_path():
    root = os.environ.get("PROJECT_ROOT") or os.path.dirname(HERE)
    return os.path.join(root, "output", ".memory-store.jsonl")


def has_topic(topic):
    path = store_path()
    if not os.path.isfile(path):
        return False
    try:
        with open(path, "rb") as fh:
            for raw in fh:
                try:
                    o = json.loads(raw.decode("utf-8", "replace"))
                except Exception:
                    continue
                if isinstance(o, dict) and o.get("topic_key") == topic:
                    return True
    except OSError:
        return False
    return False


def run(payload, project):
    summary = payload.get("compact_summary") if isinstance(payload, dict) else None
    if not isinstance(summary, str) or not normalize(summary):
        return "%s: no disponible (el frontend no entrega el resumen en este evento)." % LABEL
    sid = session_of(payload)
    if not sid:
        return "%s: no disponible (la carga no trae identificador de sesión)." % LABEL
    digest = hashlib.sha256(normalize(summary).encode("utf-8")).hexdigest()
    topic = "compact-summary/%s/%s" % (sid, digest[:16])
    if has_topic(topic):
        return "%s: confirmado, ya estaba guardado (no se duplica)." % LABEL
    cmd = ["bash", os.path.join(HERE, "memory-store.sh"), "save",
           "--type", "session-summary", "--title", "Resumen compactado %s" % sid[:12],
           "--content", summary, "--topic", topic,
           "--source", "tool:PostCompact", "--origin", "untrusted"]
    if project:
        cmd += ["--project", project]
    try:
        rc = subprocess.run(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, timeout=6).returncode
    except Exception:
        rc = -1
    if rc != 0:
        return ("%s: no confirmado, el intento de guardar falló. Comprueba el almacén con "
                "memory-store recall antes de reintentar." % LABEL)
    if has_topic(topic):
        return "%s: confirmado, guardado." % LABEL
    return ("%s: no confirmado, el intento no dio error pero la entrada no aparece. "
            "Comprueba con memory-store recall antes de reintentar." % LABEL)


def main():
    project = ""
    if len(sys.argv) >= 3 and sys.argv[1] == "--project":
        project = sys.argv[2]
    try:
        raw = sys.stdin.buffer.read(MAX_PAYLOAD + 1)
    except Exception:
        return 0
    if not raw.strip():
        return 0
    try:
        if len(raw) > MAX_PAYLOAD:
            raise ValueError("carga demasiado grande")
        payload = json.loads(raw.decode("utf-8", "replace"))
    except Exception:
        print("%s: no disponible (la carga del evento no es JSON legible)." % LABEL)
        return 0
    try:
        print(run(payload, project))
    except Exception:
        print("%s: no confirmado, error inesperado al guardar." % LABEL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
