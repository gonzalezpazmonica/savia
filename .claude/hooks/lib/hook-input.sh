#!/usr/bin/env bash
# hook-input.sh — extracción de tool_input.command sin fallo abierto (SE-453 S2).
#
#   hook_extract_command "$INPUT"  → rellena HOOK_COMMAND; devuelve 0 si evaluó, 2 si no pudo.
# Con jq: igual que `jq -r '.tool_input.command // empty'`. Sin jq: parseo con grep/sed.
# Si la entrada menciona "command" y no se logra extraer, devuelve 2 (nunca un 0 sin evaluar).
#   hook_unmeasured_exit <hook>   → registra «no medido» y sale 0 (hooks sin blocking sin jq).

_HOOK_INPUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

hook_extract_command() {
  local input="$1" raw
  HOOK_COMMAND=""
  [[ -z "$input" ]] && return 0
  if command -v jq &>/dev/null; then
    HOOK_COMMAND=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || HOOK_COMMAND=""
    return 0
  fi
  raw=$(printf '%s' "$input" | grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' | head -1)
  if [[ -z "$raw" ]]; then
    if [[ "$input" == *'"command"'* ]]; then
      echo "BLOQUEADO: sin jq no se puede evaluar el comando (instala jq)." >&2
      return 2
    fi
    return 0
  fi
  raw="${raw#*:}"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw#\"}"; raw="${raw%\"}"
  HOOK_COMMAND=$(printf '%s' "$raw" | sed -e 's/\\\\/\x01/g' -e 's/\\"/"/g' -e 's/\\\//\//g' -e 's/\\n/\n/g' -e 's/\\t/\t/g' -e 's/\x01/\\/g')
  return 0
}

hook_unmeasured_exit() {
  local hook="$1"
  # shellcheck source=/dev/null
  source "$_HOOK_INPUT_DIR/../../../scripts/lib/gate-result.sh" 2>/dev/null \
    && GATE_UNMEASURED_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$_HOOK_INPUT_DIR/../../.." && pwd)}" gate_unmeasured_record "$hook" missing_tool
  exit 0
}
