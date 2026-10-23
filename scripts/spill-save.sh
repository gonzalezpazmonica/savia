#!/usr/bin/env bash
# spill-save.sh — SE-326 S2: persiste output oversized a fichero privado.
#
# Inspirado en deepseek-harness packages/spill/spill-local + spill-policy (SE-326).
#
# Escribe el contenido COMPLETO bajo output/spill/{session}/{random}-{safeName}
# con permisos seguros (dir 0700, fichero 0o600 + open 'wx' exclusivo) para que
# un symlink plantado no pueda redirigir la escritura. Devuelve locator + hint.
#
# Best-effort: si la escritura falla (permisos, ENOSPC) → exit 1 SIN tocar nada,
# el caller conserva el output inline original.
#
# Uso:
#   spill-save.sh --session <id> --name <suggested_name> --file <src_path>
#   echo "$OUTPUT" | spill-save.sh --session <id> --name <name>
#
# Exit: 0 + preview/locator en stdout | 1 fallo de almacenamiento
set -uo pipefail

SESSION="${SAVIA_SESSION_ID:-default}"
NAME=""
SRC_FILE=""
SPILL_ROOT="${SPILL_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/output/spill}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION="$2"; shift 2 ;;
    --name)    NAME="$2";    shift 2 ;;
    --file)    SRC_FILE="$2"; shift 2 ;;
    *)         shift ;;
  esac
done

# ── Sanitizar nombre sugerido a un único segmento de path ────────────────────
[[ -z "$NAME" ]] && NAME="output.txt"
SAFE_NAME=$(printf '%s' "$NAME" | tr '/\\' '__' | tr -cd '[:alnum:]._-')
[[ -z "$SAFE_NAME" ]] && SAFE_NAME="output.txt"

# ── Root privado + sesión hash ──────────────────────────────────────────────
if [[ -n "$SRC_FILE" && ! -f "$SRC_FILE" ]]; then
  echo "[spill] ERROR: origen no existe: $SRC_FILE" >&2
  exit 1
fi

# La sesión también es un único segmento: ".." o "/" no pueden salir del root.
SAFE_SESSION=$(printf '%s' "$SESSION" | tr '/\\' '__' | tr -cd '[:alnum:]._-')
[[ -z "$SAFE_SESSION" || "$SAFE_SESSION" == "." || "$SAFE_SESSION" == ".." ]] && SAFE_SESSION="default"
SESSION_DIR="$SPILL_ROOT/$SAFE_SESSION"
if [[ -L "$SESSION_DIR" ]]; then
  echo "[spill] ERROR: el directorio de sesión es un symlink: $SESSION_DIR" >&2
  exit 1
fi
if ! mkdir -p "$SESSION_DIR" 2>/dev/null; then
  echo "[spill] ERROR: no se pudo crear $SESSION_DIR" >&2
  exit 1
fi
chmod 0700 "$SESSION_DIR" 2>/dev/null || true

# ── Nombre final: random + safeName ─────────────────────────────────────────
RANDOM_SUFFIX="$(od -An -N6 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
if [[ -z "$RANDOM_SUFFIX" ]]; then
  RANDOM_SUFFIX="$$$(date +%s)"
fi
DEST="$SESSION_DIR/${RANDOM_SUFFIX}-${SAFE_NAME}"

# ── Escritura exclusiva ('wx') — un symlink plantado falla seguro ────────────
if [[ -n "$SRC_FILE" ]]; then
  if ! python3 -c "
import os, sys
src, dst = sys.argv[1], sys.argv[2]
fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with open(src, 'rb') as fin, os.fdopen(fd, 'wb') as fout:
        fout.write(fin.read())
except BaseException:
    try: os.unlink(dst)
    except OSError: pass
    raise
" "$SRC_FILE" "$DEST" 2>/dev/null; then
    echo "[spill] ERROR: no se pudo escribir $DEST" >&2
    exit 1
  fi
else
  if ! python3 -c "
import os, sys
dst = sys.argv[1]
fd = os.open(dst, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
try:
    with os.fdopen(fd, 'wb') as fout:
        fout.write(sys.stdin.buffer.read())
except BaseException:
    try: os.unlink(dst)
    except OSError: pass
    raise
" "$DEST" 2>/dev/null; then
    echo "[spill] ERROR: no se pudo escribir $DEST" >&2
    exit 1
  fi
fi

BYTES=$(wc -c < "$DEST" 2>/dev/null || echo 0)

# ── Preview head/tail (≈40 líneas) + locator + hint ─────────────────────────
PREVIEW_LINES=20
HEAD_PREVIEW=$(sed -n "1,${PREVIEW_LINES}p" "$DEST" 2>/dev/null || true)
TAIL_PREVIEW=$(tail -n "$PREVIEW_LINES" "$DEST" 2>/dev/null || true)

BLOCK="--- preview (primeras ${PREVIEW_LINES} líneas) ---
${HEAD_PREVIEW}
--- preview (últimas ${PREVIEW_LINES} líneas) ---
${TAIL_PREVIEW}
--- fin preview ---
[spill] output completo en ${DEST} (${BYTES} bytes)
[spill] usa Read/Grep sobre esa ruta para el contenido íntegro"
printf '%s\n' "$BLOCK"

exit 0
