#!/usr/bin/env bash
# SE-345 — Mind Virus Defense: scan memory surfaces before auto-load.
#
# Scans the memory that Savia auto-loads on session start against
# scripts/mind-virus/detect.py. Report-only by default; never auto-modifies
# files (CRIT-001: read + report, quarantine only with explicit flag).
#
# Usage:
#   bash scripts/mind-virus/scan-memory.sh                 # report all surfaces
#   bash scripts/mind-virus/scan-memory.sh --json          # machine-readable
#   bash scripts/mind-virus/scan-memory.sh --only-malicious  # exit 1 if any malicious
#
# Exit codes: 0 ok | 1 any malicious (with --only-malicious) | 2 usage/scan error
set -uo pipefail

# Raíz del repo del propio script (scripts/mind-virus/ → ../..), no el directorio actual: lanzado desde
# fuera del repo no encontraba el detector.
ROOT="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
DETECT="$ROOT/scripts/mind-virus/detect.py"
MODE="text"
ONLY_MALICIOUS=false

for a in "$@"; do
  case "$a" in
    --json) MODE="json" ;;
    --only-malicious) ONLY_MALICIOUS=true ;;
    -h|--help) echo "Usage: scan-memory.sh [--json] [--only-malicious]"; exit 0 ;;
    *) echo "Unknown arg: $a" >&2; exit 2 ;;
  esac
done

# ── Memory surfaces (existing in this workspace) ────────────────────────────
# Path:label pairs. Add here when new persistent memory lands.
surfaces=(
  "$ROOT/.claude/external-memory/auto/MEMORY.md|auto-MEMORY"
  "$HOME/.savia-memory/auto/MEMORY.md|savia-memory-auto"
  "$ROOT/.claude/profiles/savia.md|profile-savia"
  "$ROOT/.claude/profiles/active-user.md|profile-active-user"
  "$ROOT/docs/critical-facts.md|critical-facts"
  "$ROOT/CLAUDE.md|claude-md"
  "$ROOT/CONSTITUCION.md|constitucion"
)

malicious=0
errors=0
declare -a rows=()

# Sin detector no hay escaneo: exit 2 (error de escaneo), nunca un «0 malicious» que parezca limpio.
if [[ ! -f "$DETECT" ]]; then
  echo "ERROR: detector no disponible: $DETECT" >&2
  exit 2
fi

# Batch scan: single python process, all surfaces at once (fast: ~60ms total
# vs ~500ms for per-file subprocess). Honours CRIT-001 (all local).
{
  SURFACE_LIST=""
  for entry in "${surfaces[@]:-}"; do
    [[ -z "$entry" ]] && continue
    path="${entry%%|*}"; label="${entry##*|}"
    [[ -f "$path" ]] || continue
    SURFACE_LIST+="${path}|${label}
"
  done
  if ! MAS_OUT=$(printf '%s' "$SURFACE_LIST" | python3 "$DETECT" --batch 2>/dev/null); then
    echo "ERROR: el detector falló al escanear las superficies de memoria" >&2
    exit 2
  fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    rows+=("$line")
    # Antes nadie contaba: malicious era siempre 0 y el load gate nunca avisaba ni bloqueaba.
    case "$(cut -d'|' -f2 <<< "$line")" in
      malicious) malicious=$((malicious + 1)) ;;
      error) errors=$((errors + 1)) ;;
    esac
  done < <(printf '%s\n' "$MAS_OUT")
}

# Código de salida: 1 si hay malicious y se pidió --only-malicious; 2 si alguna superficie no se pudo leer.
finish() {
  [[ "$ONLY_MALICIOUS" == "true" && "$malicious" -gt 0 ]] && exit 1
  [[ "$errors" -gt 0 ]] && exit 2
  exit 0
}

if [[ "$MODE" == "json" ]]; then
  python3 - "$malicious" "${rows[@]}" <<'PY'
import json, sys
malicious = int(sys.argv[1])
files = []
for r in sys.argv[2:]:
    label, verdict, score, signals = r.split("|", 3)
    files.append({"path": label, "verdict": verdict, "score": int(score), "signals": signals})
print(json.dumps({"malicious": malicious, "files": files}, ensure_ascii=False, indent=2))
PY
  finish
fi

echo "=== Mind Virus Defense — scan-memory ==="
for r in "${rows[@]:-}"; do
  IFS='|' read -r label verdict score signals <<< "$r"
  printf "  %-28s %-10s score=%-3s %s\n" "$label" "$verdict" "$score" "$signals"
done
echo "malicious total: ${malicious}"
[[ "$errors" -gt 0 ]] && echo "errores de lectura: ${errors}"
finish