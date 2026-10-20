#!/usr/bin/env bash
set -uo pipefail
# turn-budget-inject.sh — SE-445 S2: presupuesto de turnos visible para agentes autonomos.
#
# Inyecta una linea «turnos usados/maximo, minutos restantes del time-box» como contexto, para que
# el agente converja en lugar de abortar en seco. Cada bloque declara que sustituye a los
# anteriores; el hook solo emite el vigente (el contexto previo lo retira el frontend o el modelo
# lo ignora por la marca). Patron de model-tier-inject.sh. Nunca bloquea (exit 0).
#
# Activo solo con SAVIA_TURN_BUDGET=on Y modo autonomo (rama agent/* de CLAUDE_PROJECT_DIR o
# SAVIA_AUTONOMOUS_RUN=1). OFF por defecto: la spec exige medir antes de activarlo por defecto.
#
# Eventos: PreToolUse cuenta un turno; UserPromptSubmit solo muestra el bloque (OpenCode inyecta
# contexto en el prompt, no en la llamada a herramienta).
# Config (env): SAVIA_TURN_BUDGET_MAX (100), SAVIA_TURN_BUDGET_MINUTES (AGENT_TASK_TIMEOUT_MINUTES o 15).
# Estado: output/turn-budget/{session}.json. Sin stdout salvo el JSON del contexto.
# Spec: docs/specs/SE-445-autonomous-execution-safeguards.spec.md

[[ "${SAVIA_TURN_BUDGET:-off}" == "on" ]] || exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
AUTONOMOUS=0
[[ "${SAVIA_AUTONOMOUS_RUN:-}" == "1" ]] && AUTONOMOUS=1
if [[ $AUTONOMOUS -eq 0 ]]; then
  BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || true)
  [[ "$BRANCH" == agent/* ]] && AUTONOMOUS=1
fi
[[ $AUTONOMOUS -eq 1 ]] || exit 0

INPUT=""
[[ -t 0 ]] || INPUT=$(timeout 3 cat 2>/dev/null) || true
[[ -z "$INPUT" ]] && exit 0

HOOK_INPUT="$INPUT" STATE_DIR="$PROJECT_DIR/output/turn-budget" python3 - <<'PY' || true
import json, math, os, re, sys, time

try:
    data = json.loads(os.environ["HOOK_INPUT"])
except ValueError:
    sys.exit(0)
event = data.get("hook_event_name") or "PreToolUse"
if event not in ("PreToolUse", "UserPromptSubmit"):
    sys.exit(0)

def env_int(name, default):
    try:
        return max(1, int(os.environ.get(name, "")))
    except ValueError:
        return default

max_turns = env_int("SAVIA_TURN_BUDGET_MAX", 100)
minutes = env_int("SAVIA_TURN_BUDGET_MINUTES", env_int("AGENT_TASK_TIMEOUT_MINUTES", 15))

session = re.sub(r"[^A-Za-z0-9._-]", "_", str(data.get("session_id") or os.environ.get("CLAUDE_SESSION_ID") or "default"))[:96]
agent = re.sub(r"[^A-Za-z0-9._-]", "_", str(data.get("agent_id") or ""))[:64]
path = os.path.join(os.environ["STATE_DIR"], f"{session}{'.' + agent if agent else ''}.json")

try:
    import fcntl
    os.makedirs(os.environ["STATE_DIR"], exist_ok=True)
    lock = open(path + ".lock", "w")
    fcntl.flock(lock, fcntl.LOCK_EX)
except (ImportError, OSError):
    sys.exit(0)

now = time.time()
try:
    state = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    state = {}
state.setdefault("start", now)
state.setdefault("turns", 0)
if event == "PreToolUse":
    state["turns"] += 1
try:
    tmp = path + ".tmp"
    json.dump(state, open(tmp, "w", encoding="utf-8"))
    os.replace(tmp, path)
except OSError:
    pass

turns = state["turns"]
left = max(0, math.ceil(minutes - (now - state["start"]) / 60))
text = (f"[savia-budget] Este bloque sustituye a cualquier [savia-budget] anterior: "
        f"turnos {turns}/{max_turns}, minutos restantes {left}.")
if turns >= 0.9 * max_turns or left <= max(1, minutes // 5):
    text += " Presupuesto casi agotado: converge, cierra lo esencial y reporta; no abras trabajo nuevo."

print(json.dumps({"hookSpecificOutput": {"hookEventName": event, "additionalContext": text, "saviaLevel": "N1"}}))
PY
exit 0
