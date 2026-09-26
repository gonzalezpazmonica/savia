#!/bin/bash
set -uo pipefail
# cache-hygiene-hook.sh — SE-371: activación runtime de la higiene de caché.
#
# Se registra en .claude/settings.json en tres momentos:
#   SessionStart     start    → snapshot del prefijo + marker de sesión activa
#   UserPromptSubmit preturn  → detecta mutación del prefijo (log, nunca bloquea)
#   SessionEnd       end      → limpia marker + regeneración diferida si hubo drift
#
# La congelación de AGENTS.md/SKILLS.md durante la sesión la aplican los
# generadores al ver el marker data/.cache-session-active (o SAVIA_SESSION_ACTIVE).
# CRIT-001: todo local. Time-box: <15ms en preturn, <200ms en start/end.
_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MARKER="$_ROOT/data/.cache-session-active"
LOG="$_ROOT/output/.cache-hygiene.log"
_START=$SECONDS

# Drain stdin (hook JSON) — nunca bloquea al padre.
cat >/dev/null 2>&1 || true

_log() { mkdir -p "$(dirname "$LOG")"; printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo '?')" "$1" >> "$LOG" 2>/dev/null || true; }

# regeneración diferida: solo si hay drift real (evita reescribir igual)
_deferred_regen() {
  bash "$_ROOT/scripts/agents-md-generate.sh" --check >/dev/null 2>&1
  [[ $? -eq 1 ]] && bash "$_ROOT/scripts/agents-md-generate.sh" --apply >/dev/null 2>&1
  bash "$_ROOT/scripts/skills-md-generate.sh" --check >/dev/null 2>&1
  [[ $? -eq 1 ]] && bash "$_ROOT/scripts/skills-md-generate.sh" --apply >/dev/null 2>&1
  return 0
}

case "${1:-}" in
  start)
    mkdir -p "$_ROOT/data" "$_ROOT/output"
    bash "$_ROOT/scripts/cache-hygiene.sh" snapshot --out "$_ROOT/data/cache-prefix.snapshot" >/dev/null 2>&1 || true
    : > "$MARKER"
    _log "start: snapshot prefijo + sesión activa"
    ;;
  preturn)
    # No bloquear jamás: si el check tarda más del presupuesto, salir limpio.
    if (( SECONDS - _START > 1 )); then exit 0; fi
    if [[ ! -f "$_ROOT/data/cache-prefix.snapshot" ]]; then exit 0; fi
    out=$(bash "$_ROOT/scripts/cache-hygiene.sh" check --out "$_ROOT/data/cache-prefix.snapshot" 2>&1) || {
      _log "preturn MUTATED: $(echo "$out" | grep '^MUTATED' | tr '\n' ';')"
      # Silencioso para el prompt: el prefijo no debe contaminarse con ruido.
    }
    exit 0
    ;;
  end)
    rm -f "$MARKER" 2>/dev/null || true
    _deferred_regen
    # SE-371 activación: captura automática de métricas de cache al cerrar sesión.
    # Lee opencode.db local (CRIT-001) con dedupe por session — idempotente y
    # no-bloqueante; fallos solo se registran en el log.
    if bash "$_ROOT/scripts/cache-metrics.sh" capture >> "$LOG" 2>&1; then
      :
    else
      _log "capture: error no crítico al ingerir métricas"
    fi
    _log "end: marker limpio + regeneración diferida + métricas"
    ;;
  *) exit 0 ;;
esac
exit 0
