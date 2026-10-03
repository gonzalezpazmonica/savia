#!/bin/bash
set -uo pipefail
# shield-autostart.sh — Garantiza que Savia Shield (daemon + proxy) este up.
# Fire-and-forget: lanza shield-launcher.py en segundo plano (trap HUP + disown)
# para que sobreviva al cierre del hook (DETACHED_PROCESS equivalente en Windows).
# El hook NO espera a la red: la salud del daemon (:8444, tarda por spaCy) y del
# proxy (:8443) se comprueba en segundo plano y queda en un fichero de estado
# que muestra el siguiente arranque.
# WSL: set PATH explícito por si el hook corre en shell no-interactive.
#
# Salida limpia si algo falla
trap 'printf "{\"hookSpecificOutput\":{\"hookEventName\":\"SessionStart\",\"additionalContext\":\"Shield autostart: ERR line %s\"}}\n" "$LINENO"; exit 0' ERR

LOG="$HOME/.savia/shield-autostart.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
echo "[$(date +%H:%M:%S)] shield-autostart: starting" >> "$LOG"

# PATH ampliado para WSL (hooks SessionStart no cargan .bashrc)
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/.local/bin:$HOME/bin:$PATH"

SAVIA_ENV="$(dirname "${BASH_SOURCE[0]}")/../../scripts/savia-env.sh"
if [ -f "$SAVIA_ENV" ]; then
  source "$SAVIA_ENV" 2>>"$LOG"
fi
export CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-${SAVIA_WORKSPACE_DIR:-$PWD}}"
read -r -t 0.1 _HOOK_INPUT 2>/dev/null || true

# CI-mode / non-interactive: skip (avoid latency on CI benchmarks)
if [[ "${CI:-}" == "true" || "${GITHUB_ACTIONS:-}" == "true" ]]; then
  echo "CI/GHA=true, skipping" >> "$LOG"
  exit 0
fi

# Opt-in: the NER layer still yields false positives on technical prose, so the
# daemon only autostarts with SAVIA_SHIELD_AUTOSTART=on. Without it,
# data-sovereignty-gate.sh keeps the regex fallback. Headless runs always skip.
# Note: hooks ALWAYS receive the payload on a stdin pipe, so `-t 0` cannot
# tell interactive sessions apart (it made autostart a permanent no-op).
if [[ "${SAVIA_SHIELD_AUTOSTART:-off}" != "on" || "${CLAUDE_CODE_ENTRYPOINT:-}" == sdk-* ]]; then
  echo "autostart off (SAVIA_SHIELD_AUTOSTART=${SAVIA_SHIELD_AUTOSTART:-off}, entrypoint=${CLAUDE_CODE_ENTRYPOINT:-}), skipping" >> "$LOG"
  exit 0
fi

# Respeta el toggle global de Shield
if [ "${SAVIA_SHIELD_ENABLED:-true}" = "false" ]; then
  echo "SAVIA_SHIELD_ENABLED=false, skipping" >> "$LOG"
  exit 0
fi

DAEMON_PORT="${SAVIA_SHIELD_PORT:-8444}"
PROXY_PORT="${SAVIA_SHIELD_PROXY_PORT:-8443}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
STATE="${SAVIA_SHIELD_STATE:-$HOME/.savia/shield-autostart.state}"

# Launcher existe?
LAUNCHER="$PROJECT_DIR/scripts/shield-launcher.py"
if [ ! -f "$LAUNCHER" ]; then
  echo "launcher not found: $LAUNCHER" >> "$LOG"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Shield: launcher no encontrado"}}\n'
  exit 0
fi

# Resultado del arranque anterior (clave=valor; se valida, nunca se hace source)
_ts=""; _d=""; _p=""
if [ -f "$STATE" ]; then
  while IFS='=' read -r _k _v; do
    case "$_k=$_v" in
      ts=[0-9]*)                _ts="$_v"; [[ "$_v" =~ ^[0-9]+$ ]] || _ts="" ;;
      daemon=up|daemon=down)    _d="$_v" ;;
      proxy=up|proxy=down)      _p="$_v" ;;
    esac
  done < "$STATE"
fi
_word() { [ "$1" = "up" ] && echo "activo" || echo "no responde"; }
_age=-1
if [ -n "$_ts" ]; then
  _age=$(( $(date +%s) - _ts )); [ "$_age" -lt 0 ] && _age=0
fi
# Resultado de más de 24 h: no se presenta como estado actual
if [ -n "$_d" ] && [ -n "$_p" ] && [ "$_age" -ge 0 ] && [ "$_age" -le 86400 ]; then
  if   [ "$_age" -lt 120 ];  then _when="${_age}s"
  elif [ "$_age" -lt 7200 ]; then _when="$(( _age / 60 ))min"
  else                            _when="$(( _age / 3600 ))h"; fi
  MSG="Shield: arranque lanzado en segundo plano; último resultado (hace $_when): daemon $(_word "$_d"), proxy $(_word "$_p")"
else
  MSG="Shield: arranque lanzado en segundo plano (resultado en ~/.savia/shield-autostart.log)"
fi

# Arranque y comprobación de salud en segundo plano: el hook no espera a la red.
# shield-launcher.py start es idempotente (si el servicio ya responde no relanza)
# y espera él mismo a que el daemon cargue spaCy (hasta 20s). trap HUP + disown
# para sobrevivir al cierre del hook. flock evita dos arranques simultáneos.
mkdir -p "$(dirname "$STATE")" 2>/dev/null || true
(
  trap '' HUP
  if command -v flock >/dev/null 2>&1; then
    exec 9>"$STATE.lock"
    if ! flock -n 9; then
      echo "[$(date +%H:%M:%S)] otro arranque en curso, se omite" >> "$LOG"
      exit 0
    fi
  fi
  python3 "$LAUNCHER" start
  d=down; p=down
  curl -sf --max-time 2 "http://127.0.0.1:${DAEMON_PORT}/health" >/dev/null 2>&1 && d=up
  curl -sf --max-time 2 "http://127.0.0.1:${PROXY_PORT}/health" >/dev/null 2>&1 && p=up
  echo "[$(date +%H:%M:%S)] resultado: daemon=$d proxy=$p"
  tmp="$STATE.$BASHPID"
  printf 'ts=%s\ndaemon=%s\nproxy=%s\n' "$(date +%s)" "$d" "$p" > "$tmp" && mv -f "$tmp" "$STATE"
) </dev/null >>"$LOG" 2>&1 &
disown 2>/dev/null || true

echo "[$(date +%H:%M:%S)] launcher en segundo plano (daemon :${DAEMON_PORT}, proxy :${PROXY_PORT})" >> "$LOG"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$MSG"
exit 0
