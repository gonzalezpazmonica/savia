#!/usr/bin/env bash
set -uo pipefail
# .opencode/hooks/recursion-guard.sh — PreToolUse hook
# Blocks autonomous loop launch when already inside a running loop.
# Ref: SPEC-RECURSION-GUARD, docs/rules/domain/autonomous-safety.md
# Exit codes: 0=allow, 2=block (recursive loop detected)
# Env: SAVIA_LOOP_CONTEXT="loop_name:depth", OPENCODE_TOOL_INPUT=JSON
#   SAVIA_LOOP_CONTEXT  format: "loop_name:depth"  e.g. "overnight-sprint:1"
#   OPENCODE_TOOL_INPUT  JSON string of the current tool call input

set -uo pipefail

# Loop pattern list
LOOP_PATTERNS=(
  "overnight-sprint"
  "code-improvement-loop"
  "tech-research-agent"
  "loop_skill"
)

_detect_loop() {
  local input="${1:-}"
  for pattern in "${LOOP_PATTERNS[@]}"; do
    if [[ "$pattern" == "loop_skill" ]]; then
      # Match as JSON field OR as standalone word (avoid partial matches like my_loop_skill_ext)
      if grep -qE '"loop_skill"\s*:|loop_skill[^_[:alnum:]]|loop_skill$' <<<"$input"; then
        printf '%s' "$pattern"
        return 0
      fi
    else
      if grep -qF "$pattern" <<<"$input"; then
        printf '%s' "$pattern"
        return 0
      fi
    fi
  done
  return 1
}

main() {
  # No loop context — always allow
  if [[ -z "${SAVIA_LOOP_CONTEXT:-}" ]]; then
    exit 0
  fi

  # Claude Code pasa la entrada por stdin; OPENCODE_TOOL_INPUT queda como respaldo.
  # stdin es la fuente autorizada; la variable solo vale de respaldo si stdin llega vacío (una variable
  # heredada en el entorno no puede sustituir a la entrada real y anular la evaluación).
  local tool_input=""
  if [[ ! -t 0 ]]; then tool_input=$(timeout 3 cat 2>/dev/null || true); fi
  [[ -z "$tool_input" ]] && tool_input="${OPENCODE_TOOL_INPUT:-}"
  # Dentro de un bucle activo el guard falla cerrado: sin entrada, o con una que no puede decodificar,
  # bloquea. JSON: se compara el texto DECODIFICADO (un escape \uXXXX equivale a su carácter) y todas
  # las rutas de claves, también las de contenedores vacíos; here-strings sin SIGPIPE.
  local trimmed="${tool_input#"${tool_input%%[![:space:]]*}"}"
  if [[ -z "$trimmed" ]]; then
    printf 'BLOCKED [recursion-guard]: sin entrada que evaluar dentro de un bucle activo.\n'
    exit 2
  fi
  if [[ "$trimmed" == \{* || "$trimmed" == \[* ]]; then
    local decoded
    if ! command -v jq &>/dev/null; then
      if [[ "$trimmed" == *'\u'* ]]; then
        printf 'BLOCKED [recursion-guard]: sin jq no se pueden decodificar los escapes de la entrada.\n'
        exit 2
      fi
    elif ! decoded=$(jq -r '[paths as $p | ($p | map(tostring) | join(".")), (getpath($p) | select(type != "object" and type != "array") | tostring)] | join("\n")' <<<"$trimmed" 2>/dev/null); then
      printf 'BLOCKED [recursion-guard]: entrada malformada dentro de un bucle activo.\n'
      exit 2
    else
      tool_input="$decoded"
    fi
  fi

  local detected_loop
  if ! detected_loop="$(_detect_loop "$tool_input")"; then
    exit 0
  fi

  printf 'BLOCKED [recursion-guard]: Loop recursion detected.\n'
  printf '  Current context: %s\n' "${SAVIA_LOOP_CONTEXT}"
  printf "  Cannot launch '%s' from inside a running loop.\n" "${detected_loop}"
  printf "  To run nested loops, use 'SAVIA_LOOP_CONTEXT=' to clear (autonomous-safety Rule applies).\n"
  printf "  Tool input (truncated): %s\n" "${tool_input:0:100}"
  exit 2
}

main "$@"
