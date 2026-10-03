#!/usr/bin/env bash
# transcriptor-mark-digested.sh — marcar una reunion como digerida
# Usage: bash scripts/transcriptor-mark-digested.sh [--force] <carpeta>
#
# <carpeta>: nombre bajo $SAVIA_TRANSCRIPTOR_DIR/reuniones o ruta con '/'.
# Exit: 0 marcada (o ya lo estaba) · 1 error (uso, carpeta, meta.json ilegible,
# python3 ausente, escritura fallida) · 3 reunion sin transcribir (usa --force
# para marcarla igualmente).
# La escritura es atomica (fichero temporal + rename en la misma carpeta): un
# lector concurrente ve el meta.json anterior o el nuevo, nunca uno truncado.
# Tras escribir, relee el fichero y solo declara exito si digested es true.
set -uo pipefail

TRANSCRIPTOR_DIR="${SAVIA_TRANSCRIPTOR_DIR:-$HOME/.savia/transcriptor}"
MEETINGS_DIR="$TRANSCRIPTOR_DIR/reuniones"

FORCE=0
if [[ "${1:-}" == "--force" ]]; then FORCE=1; shift; fi
SESSION="${1:-}"
if [[ -z "$SESSION" ]]; then
  echo "Usage: transcriptor-mark-digested.sh [--force] <carpeta>" >&2
  exit 1
fi

# Resolver: si es un nombre (YYYY-MM-DD-HH-MM) o una ruta
if [[ "$SESSION" == */* ]]; then
  SESSION_PATH="${SESSION%/}"
else
  if [[ "$SESSION" == "." || "$SESSION" == ".." ]]; then
    echo "ERROR: nombre de reunion invalido: $SESSION" >&2
    exit 1
  fi
  SESSION_PATH="$MEETINGS_DIR/$SESSION"
fi

if [[ ! -d "$SESSION_PATH" ]]; then
  echo "ERROR: no se encuentra la reunion $SESSION_PATH" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 no disponible; la reunion NO se ha marcado" >&2
  exit 1
fi

python3 - "$SESSION_PATH" "$FORCE" <<'PY'
import json
import os
import sys
import tempfile
from datetime import datetime, timezone

session, force = sys.argv[1], sys.argv[2] == "1"
name = os.path.basename(session)
meta_path = os.path.join(session, "meta.json")


def fail(msg, code=1):
    print(f"ERROR: {msg}; la reunion NO se ha marcado", file=sys.stderr)
    sys.exit(code)


if os.path.isfile(meta_path):
    try:
        with open(meta_path, encoding="utf-8") as fh:
            meta = json.load(fh)
    except (OSError, ValueError) as exc:
        fail(f"meta.json ilegible en {name}: {exc}")
    if not isinstance(meta, dict):
        fail(f"meta.json de {name} no es un objeto JSON")
    mode = os.stat(meta_path).st_mode & 0o7777
elif os.path.exists(meta_path):
    fail(f"{meta_path} existe pero no es un fichero")
else:
    meta, mode = {}, 0o644

if meta.get("digested") is True:
    print(f"Reunion ya estaba digerida: {name}")
    sys.exit(0)

if "transcribed" in meta:
    transcribed = meta.get("transcribed") is True
else:
    transcribed = any(os.path.isfile(os.path.join(session, f))
                      for f in ("transcript.md", "transcript.vtt"))
if not transcribed and not force:
    fail(f"{name} aun no esta transcrita (grabacion o transcripcion en curso); "
         "usa --force si de verdad se digirio", 3)

meta["digested"] = True
meta["digested_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")

fd, tmp = tempfile.mkstemp(prefix=".meta.json.", suffix=".tmp", dir=session)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
        fh.flush()
        os.fsync(fh.fileno())
    os.chmod(tmp, mode)
    os.replace(tmp, meta_path)
except OSError as exc:
    try:
        os.unlink(tmp)
    except OSError as cleanup_exc:
        print(f"AVISO: no se pudo borrar el temporal {tmp}: {cleanup_exc}", file=sys.stderr)
    fail(f"no se pudo escribir {meta_path}: {exc}")

try:
    with open(meta_path, encoding="utf-8") as fh:
        ok = json.load(fh).get("digested") is True
except (OSError, ValueError) as exc:
    fail(f"verificacion tras escribir {meta_path} fallida: {exc}")
if not ok:
    fail(f"verificacion tras escribir {meta_path}: digested no quedo en true")
print(f"Marcada como digerida: {name}")
PY
