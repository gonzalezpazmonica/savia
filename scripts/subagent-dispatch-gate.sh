#!/usr/bin/env bash
# subagent-dispatch-gate.sh — SE-313 S7c: gate de resolución de tiers + telemetría.
# Valida que el modelo de un subagente resuelve a un ID existente en el runtime.
# Exit codes: 0 ok, 1 not found, 2 usage.
set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/savia-env.sh"
AGENT_NAME=""; TIER=""; MODEL_ID=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT_NAME="$2"; shift 2 ;;
    --tier)  TIER="$2"; shift 2 ;;
    --model) MODEL_ID="$2"; shift 2 ;;
    *) exit 2 ;;
  esac
done
REPO_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
REGISTRY="$REPO_ROOT/config/model-registry.json"
EMIT="$REPO_ROOT/scripts/otel-emit.sh"

# Si no llega tier/model explicito, derivar el tier del frontmatter del agente
# (.opencode/agents/{name}.md -> model_tier: mid|heavy|fast). Fallback: mid.
derive_tier() {
  local agent="$1"
  local mdfile="$REPO_ROOT/.opencode/agents/${agent}.md"
  if [[ -f "$mdfile" ]]; then
    local t
    t="$(grep -m1 -E '^model(_tier)?:' "$mdfile" | sed -E 's/^model(_tier)?:[[:space:]]*//' | tr -d '"' )"
    case "$t" in
      heavy|mid|fast) echo "$t"; return ;;
    esac
  fi
  echo "mid"
}

RESOLVED=""
if [[ -n "$MODEL_ID" ]]; then
  RESOLVED="$(savia_resolve_model "$MODEL_ID")"
elif [[ -n "$TIER" ]]; then
  RESOLVED="$(savia_resolve_model "$TIER")"
else
  TIER="$(derive_tier "$AGENT_NAME")"
  RESOLVED="$(savia_resolve_model "$TIER")"
fi
exists_in_registry() {
  local id="$1"
  if [[ -f "$REGISTRY" ]] && python3 -c "
import json, sys
reg = json.load(open('$REGISTRY'))
sys.exit(0 if '$id' in reg.get('models', []) else 1)
" 2>/dev/null; then
    return 0
  fi
  if command -v opencode >/dev/null 2>&1 && opencode models 2>/dev/null | grep -qx "$id"; then
    return 0
  fi
  return 1
}
if exists_in_registry "$RESOLVED"; then
  [[ -x "$EMIT" ]] && "$EMIT" dispatch.resolved agent_name="$AGENT_NAME" tier="$TIER" requested_model="${MODEL_ID:-$TIER}" resolved_model="$RESOLVED"
  echo "OK: $AGENT_NAME → $RESOLVED"
  exit 0
else
  [[ -x "$EMIT" ]] && "$EMIT" dispatch.failed agent_name="$AGENT_NAME" tier="$TIER" requested_model="${MODEL_ID:-$TIER}" resolved_model="$RESOLVED" error="Model not found: $RESOLVED"
  echo "ERROR: $AGENT_NAME → '$RESOLVED' no existe en el registry del runtime." >&2
  echo "  Causa probable: preferencias de modelo sin prefijo de provider, o tier no declarado." >&2
  echo "  Fix: revisar ~/.savia/preferences.yaml (model_heavy/mid/fast y provider)." >&2
  exit 1
fi
