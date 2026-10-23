#!/usr/bin/env bash
# telemetry-tail-sample.sh — SE-313 S4: sampling tail + retención + rotación.
#
# Aplica las políticas de config/telemetry-policies.yaml sobre
# output/telemetry-events.jsonl:
#   - Rotación: al superar rotation_lines, rota a telemetry-events.{ts}.jsonl
#   - Retención: purga ficheros con más de retention_days de antigüedad
#   - Redacción: con SAVIA_TELEMETRY_REDACT=1 deja solo {ts, event}
#
# Uso:
#   telemetry-tail-sample.sh [rotate|prune|redact|check]
# Default: check (no muta nada; reporta estado y violaciones de política).
#
# Exit codes: 0 ok, 1 violación de política (retention/rotación), 2 usage.
set -uo pipefail

MODE="${1:-check}"
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
POLICY="$REPO_ROOT/config/telemetry-policies.yaml"
TELEMETRY_FILE="${SAVIA_TELEMETRY_FILE:-$REPO_ROOT/output/telemetry-events.jsonl}"

# ── Leer políticas (python3 + yaml; sin dependencias) ────────────────────────
RETENTION_DAYS=180
ROTATION_LINES=10000
ROTATION_MAX_FILES=20

read_policy() {
  if [[ -f "$POLICY" ]] && command -v python3 >/dev/null 2>&1; then
    local out
    out="$(python3 -c "
import yaml
p = yaml.safe_load(open('$POLICY'))
print(p.get('retention_days', 180))
print(p.get('rotation_lines', 10000))
print(p.get('rotation_max_files', 20))
" 2>/dev/null)"
    if [[ $? -eq 0 ]]; then
      RETENTION_DAYS="$(echo "$out" | sed -n 1p)"
      ROTATION_LINES="$(echo "$out" | sed -n 2p)"
      ROTATION_MAX_FILES="$(echo "$out" | sed -n 3p)"
    fi
  fi
}
read_policy

# ── Redacción (SAVIA_TELEMETRY_REDACT=1 → solo ts+event) ────────────────────
redact_file() {
  local src="$1"
  local tmp
  tmp="$(mktemp)"
  # Conserva schema + ts + event; elimina todo lo demás.
  jq -c '{schema:.schema, ts:.ts, event:.event}' "$src" > "$tmp" 2>/dev/null \
    && mv "$tmp" "$src"
}

# ── Rotación ────────────────────────────────────────────────────────────────
rotate() {
  [[ -f "$TELEMETRY_FILE" ]] || return 0
  local lines
  lines="$(wc -l < "$TELEMETRY_FILE" 2>/dev/null || echo 0)"
  if [[ "$lines" -gt "$ROTATION_LINES" ]]; then
    local ts
    ts="$(date -u +%Y%m%dT%H%M%SZ)"
    local rotated="$TELEMETRY_FILE.${ts}"
    mv "$TELEMETRY_FILE" "$rotated"
    echo "rotated: $TELEMETRY_FILE -> $rotated ($lines lines)"
  fi
}

# ── Retención (purga ficheros > retention_days) ─────────────────────────────
prune() {
  local dir
  dir="$(dirname "$TELEMETRY_FILE")"
  [[ -d "$dir" ]] || return 0
  local cutoff
  cutoff="$(date -u -d "-${RETENTION_DAYS} days" +%s 2>/dev/null || date -d "-${RETENTION_DAYS} days" +%s 2>/dev/null)"
  if [[ -z "$cutoff" ]]; then
    echo "WARN: no se pudo calcular cutoff de retención" >&2
    return 0
  fi
  for f in "$dir"/telemetry-events.jsonl.*; do
    [[ -e "$f" ]] || continue
    local mtime filets
    mtime="$(stat -c %Y "$f" 2>/dev/null || echo 0)"
    if [[ "$mtime" -lt "$cutoff" ]]; then
      rm -f "$f"
      echo "pruned: $f (>${RETENTION_DAYS}d)"
    fi
  done
  # Limitar nº de ficheros rotados
  local n=0
  for f in "$dir"/telemetry-events.jsonl.*; do
    [[ -e "$f" ]] || continue
    n=$((n+1))
  done
  while [[ "$n" -gt "$ROTATION_MAX_FILES" ]]; do
    local oldest=""
    for f in "$dir"/telemetry-events.jsonl.*; do
      [[ -e "$f" ]] || continue
      if [[ -z "$oldest" ]] || [[ "$f" -ot "$oldest" ]]; then oldest="$f"; fi
    done
    [[ -n "$oldest" ]] || break
    rm -f "$oldest"
    echo "pruned (max files): $oldest"
    n=$((n-1))
  done
}

# ── Check (no muta) ─────────────────────────────────────────────────────────
check() {
  local violations=0
  if [[ -f "$TELEMETRY_FILE" ]]; then
    local lines
    lines="$(wc -l < "$TELEMETRY_FILE")"
    echo "telemetry-events.jsonl: $lines lines (rotation_threshold=$ROTATION_LINES)"
    [[ "$lines" -gt "$ROTATION_LINES" ]] && { echo "VIOLATION: over rotation threshold"; violations=$((violations+1)); }
    # Validar que todas las líneas son JSON válido con schema correcto
    local bad
    bad="$(jq -c -e 'select(.schema != "savia.event/1.0")' "$TELEMETRY_FILE" 2>/dev/null | wc -l)"
    [[ "$bad" -gt 0 ]] && { echo "VIOLATION: $bad line(s) con schema incorrecto"; violations=$((violations+1)); }
  else
    echo "telemetry-events.jsonl: no existe aún (sin eventos)"
  fi
  echo "retention_days=$RETENTION_DAYS rotation_lines=$ROTATION_LINES"
  [[ "$violations" -eq 0 ]]
}

case "$MODE" in
  rotate) rotate ;;
  prune)  prune ;;
  redact) redact_file "$TELEMETRY_FILE" ;;
  check)  check; exit $? ;;
  *) echo "usage: $0 [rotate|prune|redact|check]"; exit 2 ;;
esac
exit 0
