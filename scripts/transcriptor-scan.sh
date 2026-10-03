#!/usr/bin/env bash
# transcriptor-scan.sh — listar reuniones listas para digerir de Savia Transcriptor
# Usage: bash scripts/transcriptor-scan.sh [--all]
#
# Por defecto imprime en stdout, una por linea, las reuniones TRANSCRITAS y sin
# digerir (meta.json con transcribed true y digested distinto de true). Una
# reunion sin meta.json o sin la clave transcribed cuenta como transcrita si
# tiene transcript.md o transcript.vtt.
# Las reuniones aun en grabacion o transcripcion van a stderr como PENDIENTE y
# las de meta.json ilegible como ERROR: digerirlas ahora y marcarlas perderia
# el contenido que llegue despues.
# --all: todas las reuniones con su estado (digested=, transcribed=).
set -uo pipefail

TRANSCRIPTOR_DIR="${SAVIA_TRANSCRIPTOR_DIR:-$HOME/.savia/transcriptor}"
MEETINGS_DIR="$TRANSCRIPTOR_DIR/reuniones"
MODE="${1:-}"

case "$MODE" in
  ""|--all) ;;
  -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
  *) echo "ERROR: argumento no reconocido: $MODE (uso: transcriptor-scan.sh [--all])" >&2; exit 2 ;;
esac

if [[ ! -d "$MEETINGS_DIR" ]]; then
  echo "No hay reuniones todavia en $MEETINGS_DIR" >&2
  exit 0
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: python3 no disponible; no se puede leer meta.json" >&2
  exit 1
fi

python3 - "$MEETINGS_DIR" "$MODE" <<'PY'
import json
import os
import sys

root, mode = sys.argv[1], sys.argv[2]

for name in sorted(os.listdir(root)):
    session = os.path.join(root, name)
    if name.startswith(".") or not os.path.isdir(session):
        continue
    meta_path = os.path.join(session, "meta.json")
    meta = {}
    if os.path.isfile(meta_path):
        try:
            with open(meta_path, encoding="utf-8") as fh:
                meta = json.load(fh)
        except (OSError, ValueError) as exc:
            print(f"ERROR: meta.json ilegible en {name}: {exc}", file=sys.stderr)
            meta = None
        if meta is not None and not isinstance(meta, dict):
            print(f"ERROR: meta.json ilegible en {name}: no es un objeto JSON", file=sys.stderr)
            meta = None
    if meta is None:
        if mode == "--all":
            print(f"{name} digested=? transcribed=? meta=ilegible")
        continue
    digested = meta.get("digested") is True
    if "transcribed" in meta:
        transcribed = meta.get("transcribed") is True
    else:
        transcribed = any(os.path.isfile(os.path.join(session, f))
                          for f in ("transcript.md", "transcript.vtt"))
    if mode == "--all":
        print(f"{name} digested={digested} transcribed={transcribed}")
    elif not digested:
        if transcribed:
            print(name)
        else:
            print(f"PENDIENTE: {name} (sin transcribir todavia)", file=sys.stderr)
PY
