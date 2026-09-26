#!/bin/bash
set -uo pipefail
# shield-autostart.sh — Garantiza que Savia Shield (daemon + proxy) este up.
# Fire-and-forget: lanza shield-launcher.py con nohup+disown para que sobreviva
# al cierre del hook (usa DETACHED_PROCESS equivalente en Windows).
# Espera hasta 15s al daemon (port 8444, tarda por spaCy) y al proxy (port 8443).
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

DAEMON_PORT=8444
PROXY_PORT=8443
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

# Check rapido: daemon + proxy ya responden?
if curl -sf --max-time 1 "http://127.0.0.1:${DAEMON_PORT}/health" >/dev/null 2>&1 && \
   curl -sf --max-time 1 "http://127.0.0.1:${PROXY_PORT}/health" >/dev/null 2>&1; then
  echo "already up" >> "$LOG"
  exit 0
fi

# Launcher existe?
LAUNCHER="$PROJECT_DIR/scripts/shield-launcher.py"
if [ ! -f "$LAUNCHER" ]; then
  echo "launcher not found: $LAUNCHER" >> "$LOG"
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Shield: launcher no encontrado"}}\n'
  exit 0
fi

# Lanzar launcher con nohup + disown para que sobreviva SIGHUP al salir el hook
# y redirigir log a fichero (no a /dev/null) para depuracion
nohup python3 "$LAUNCHER" start >> "$LOG" 2>&1 &
disown

# Esperar hasta 15s a que DAEMON responda (tarda mas por spaCy/Presidio)
echo "waiting for daemon :${DAEMON_PORT}..." >> "$LOG"
for i in $(seq 1 30); do
  sleep 0.5
  if curl -sf --max-time 1 "http://127.0.0.1:${DAEMON_PORT}/health" >/dev/null 2>&1; then
    echo "daemon up after ${i}s" >> "$LOG"
    # Ahora esperar al proxy (suele arrancar en <1s)
    for j in $(seq 1 10); do
      if curl -sf --max-time 1 "http://127.0.0.1:${PROXY_PORT}/health" >/dev/null 2>&1; then
        echo "proxy up after ${i}s total" >> "$LOG"
        printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Shield up (daemon+proxy, %ss)"}}\n' "$((i/2))"
        exit 0
      fi
      sleep 0.5
    done
    # Proxy no respondio pero daemon si -> warning
    echo "proxy not responding after ${i}s (daemon ok)" >> "$LOG"
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Shield daemon up, proxy not responding"}}\n'
    exit 0
  fi
done

# Ni daemon ni proxy respondieron
echo "daemon not responding after 15s" >> "$LOG"
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Shield daemon no respondio en 15s — revisar ~/.savia/shield-autostart.log"}}\n'
exit 0
