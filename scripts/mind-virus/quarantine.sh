#!/usr/bin/env bash
# SE-345 — Mind Virus Defense: quarantine a malicious file (explicit flag only).
#
# Moves a file flagged as malicious by detect.py into the local quarantine dir.
# NEVER runs automatically (the study's risk: auto-modification is the attack).
# CRIT-001: everything stays local — quarantine dir is under the workspace.
#
# Usage:
#   bash scripts/mind-virus/quarantine.sh --quarantine <path> [--reason "text"]
#   bash scripts/mind-virus/quarantine.sh --list
#   bash scripts/mind-virus/quarantine.sh --rescan            # re-verify quarantined
set -uo pipefail

# Raíz del repo del propio script (scripts/mind-virus/ → ../..), no el directorio actual: lanzado desde
# fuera del repo no encontraba el detector.
ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DETECT="$ROOT/scripts/mind-virus/detect.py"
QUARANTINE_DIR="${SAVIA_MVD_QUARANTINE:-$ROOT/output/mvd-quarantine}"
MODE=""
PATH_ARG=""
REASON=""
EXPECT_REASON=false

# --reason toma el siguiente argumento sin cambiar el modo. Antes ponía MODE=() y la orden
# documentada «--quarantine <path> --reason texto» acababa en el uso con exit 2.
for a in "$@"; do
  if [[ "$EXPECT_REASON" == "true" ]]; then
    REASON="$a"; EXPECT_REASON=false; continue
  fi
  case "$a" in
    --quarantine) MODE="quarantine" ;;
    --list) MODE="list" ;;
    --rescan) MODE="rescan" ;;
    --reason) EXPECT_REASON=true ;;
    --*) echo "Unknown flag: $a" >&2; exit 2 ;;
    *)
      if [[ "$MODE" == "quarantine" && -z "$PATH_ARG" ]]; then
        PATH_ARG="$a"
      else
        echo "Unexpected arg: $a" >&2; exit 2
      fi
      ;;
  esac
done
[[ "$EXPECT_REASON" == "true" ]] && { echo "Error: --reason requiere un texto" >&2; exit 2; }

mkdir -p "$QUARANTINE_DIR" 2>/dev/null || true

case "$MODE" in
  list)
    ls -1 "$QUARANTINE_DIR" 2>/dev/null || echo "(vacía)"
    exit 0
    ;;
  rescan)
    echo "=== Re-verificación de cuarentena ==="
    for f in "$QUARANTINE_DIR"/*; do
      [[ -f "$f" ]] || continue
      out=$(python3 "$DETECT" "$f" 2>/dev/null) || true
      verdict=$(printf '%s' "$out" | python3 -c "import sys,json;print(json.load(sys.stdin).get('verdict','clean'))" 2>/dev/null || echo clean)
      echo "  $(basename "$f"): $verdict"
    done
    exit 0
    ;;
  quarantine)
    [[ -z "$PATH_ARG" ]] && { echo "Error: --quarantine requiere <path>" >&2; exit 2; }
    [[ -f "$PATH_ARG" ]] || { echo "Error: no existe: $PATH_ARG" >&2; exit 2; }
    out=$(python3 "$DETECT" "$PATH_ARG" 2>/dev/null) || true
    verdict=$(printf '%s' "$out" | python3 -c "import sys,json;print(json.load(sys.stdin).get('verdict','clean'))" 2>/dev/null || echo clean)
    if [[ "$verdict" != "malicious" ]]; then
      echo "Error: $PATH_ARG no es malicious (verdict=$verdict). Cuarentena solo para cargas confirmadas." >&2
      exit 2
    fi
    base=$(basename "$PATH_ARG")
    ts=$(date +%Y%m%d-%H%M%S)
    dest="$QUARANTINE_DIR/${ts}__${base}"
    mv "$PATH_ARG" "$dest"
    echo "quarantined: $PATH_ARG → $dest"
    [[ -n "$REASON" ]] && printf 'reason: %s\n' "$REASON" > "$dest.mvd-reason"
    exit 0
    ;;
  *)
    echo "Usage: quarantine.sh --quarantine <path> [--reason text] | --list | --rescan" >&2
    exit 2
    ;;
esac