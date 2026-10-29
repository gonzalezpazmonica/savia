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
  local trimmed="${input#"${input%%[![:space:]]*}"}"
  if command -v jq &>/dev/null; then
    if HOOK_COMMAND=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null); then
      return 0
    fi
    HOOK_COMMAND=""
    # Parece JSON pero no se puede leer (truncado, malformado): fallo cerrado. Texto plano: nada que evaluar.
    if [[ "$trimmed" == \{* || "$trimmed" == \[* ]]; then
      echo "BLOQUEADO: entrada del hook malformada; no se puede evaluar." >&2
      return 2
    fi
    return 0
  fi
  # Sin jq no se decodifican los escapes \uXXXX con fidelidad: si aparecen, no se puede evaluar.
  if [[ "$input" == *'\u'* && "$input" == *'"command"'* ]]; then
    echo "BLOQUEADO: sin jq no se puede decodificar la orden (instala jq)." >&2
    return 2
  fi
  raw=$(grep -oE '"command"[[:space:]]*:[[:space:]]*"([^"\\]|\\.)*"' <<<"$input" | head -1)
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
  source "$_HOOK_INPUT_DIR/gate-result.sh" 2>/dev/null \
    && GATE_UNMEASURED_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$_HOOK_INPUT_DIR/../../.." && pwd)}" gate_unmeasured_record "$hook" missing_tool
  exit 0
}

# Inicio de una orden real dentro de una línea de shell: principio, separador (; & | `), subshell ( o $(,
# o el argumento de `sh -c`/`bash -c`/`eval`; seguido de prefijos que no cambian la orden (VAR=x, env,
# command, sudo, doas, nohup, time, exec, xargs, nice, ionice, stdbuf, setsid, timeout N…, con sus
# opciones —`sudo -u root`, `env -u X`—, y las palabras then, do, else, if, elif, while, until, !, {).
# Una mención dentro de un mensaje, un echo o un grep no queda anclada.
HOOK_CMD_AT='(^|[;&|(`]|\$\(|(^|[^[:alnum:]_])((ba|z|da|k)?sh([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*c|eval)[[:space:]]+["'"'"']?)[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|(env|command|sudo|doas|nohup|time|exec|xargs|nice|ionice|stdbuf|setsid|timeout)([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*|[0-9][0-9.]*[smhd]?|then|do|else|if|elif|while|until|!|\{)[[:space:]]+)*'

# Inicio de una orden git con sus opciones globales, valores entre comillas incluidos (-c user.name="A B").
HOOK_GIT_AT="${HOOK_CMD_AT}"'(\\|[^[:space:]]*/)?git(([[:space:]]+(-C|-c|--git-dir|--work-tree)[[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"'|[^-[:space:]][^[:space:]]*("[^"]*"|'"'"'[^'"'"']*'"'"')?[^[:space:]]*))|([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?))*[[:space:]]+'

# hook_read_command <hook>: lee la entrada (variable de respaldo o stdin) y deja la orden en HOOK_COMMAND.
#   0 → evaluable (HOOK_COMMAND puede ser texto plano si llegó por la variable de respaldo)
#   2 → entrada JSON malformada: el llamador debe bloquear (fallo cerrado)
#   3 → sin entrada: se registra como «no medido» y el llamador decide (los gates de órdenes salen con 0)
hook_read_command() {
  local hook="$1" raw=""
  HOOK_COMMAND=""
  # stdin es la fuente autorizada; la variable solo vale de respaldo si stdin llega vacío (una variable
  # heredada en el entorno no puede sustituir a la entrada real y anular la evaluación).
  if [[ ! -t 0 ]]; then raw=$(timeout 3 cat 2>/dev/null || true); fi
  [[ -z "$raw" ]] && raw="${CLAUDE_TOOL_INPUT:-}"
  if [[ -z "$raw" ]]; then
    # shellcheck source=/dev/null
    source "$_HOOK_INPUT_DIR/gate-result.sh" 2>/dev/null \
      && GATE_UNMEASURED_ROOT="${CLAUDE_PROJECT_DIR:-$(cd "$_HOOK_INPUT_DIR/../../.." && pwd)}" gate_unmeasured_record "$hook" empty_input
    return 3
  fi
  local trimmed="${raw#"${raw%%[![:space:]]*}"}"
  HOOK_SESSION_CWD=""  # nunca heredado del entorno: solo el cwd que entrega el runtime en el JSON
  if [[ "$trimmed" == \{* ]]; then
    raw="$trimmed"
    if command -v jq &>/dev/null && ! printf '%s' "$raw" | jq -e . >/dev/null 2>&1; then
      echo "BLOQUEADO [$hook]: entrada del hook malformada; no se puede evaluar." >&2
      return 2
    fi
    hook_extract_command "$raw" || return 2
    HOOK_SESSION_CWD=""
    if command -v jq &>/dev/null; then
      HOOK_SESSION_CWD=$(jq -r '(.cwd // empty) | select(type == "string")' <<<"$raw" 2>/dev/null) || HOOK_SESSION_CWD=""
    fi
    return 0
  fi
  HOOK_COMMAND="$raw"
  return 0
}

# Resuelve un directorio escrito en la orden (comillas, ~, $HOME; relativo a $2). Sin expansión estática
# ($VAR, $(...), `...`, comodines) o sin directorio existente → 1. Deja la ruta física en _HOOK_RESOLVED.
_hook_resolve_dir() {
  local d="$1" base="$2"
  d="${d%\"}"; d="${d#\"}"; d="${d%\'}"; d="${d#\'}"
  d="${d/#\~/$HOME}"; d="${d/#\$HOME/$HOME}"
  [[ -z "$d" || "$d" == *'$'* || "$d" == *'`'* || "$d" == *[\*\?\[]* ]] && return 1
  [[ "$d" != /* ]] && d="$base/$d"
  [[ -d "$d" ]] || return 1
  _HOOK_RESOLVED=$(cd "$d" 2>/dev/null && pwd -P) || return 1
}

# hook_git_targets <orden> <cwd de la sesión>: repos (raíz del árbol de trabajo) sobre los que actúa cada
# `git commit` de la orden, siguiendo `cd X &&` previos (acumulativos) y `git -C X` (acumulativos, relativos
# al cd vigente). Rellena HOOK_GIT_TARGETS (únicos, en orden) y devuelve 0. Devuelve 1 y HOOK_TARGET_REASON
# si algún objetivo no se puede determinar estáticamente: --git-dir/--work-tree, rutas con variables o
# sustituciones, directorios inexistentes, fuera de un repo, o un commit que el análisis no localiza.
hook_git_targets() {
  local cmd="$1" base="${2:-$PWD}" rest m prefix cwd dir top t
  local re_commit="${HOOK_GIT_AT}commit([[:space:]]|\$)"
  local nl=$'\n'
  local re_cd='(^|[;&|('"$nl"'`]|\$\()[[:space:]]*cd[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:];&|)]*)[[:space:]]*(&&|;|\|\||\))?'
  local re_c='(^|[[:space:]])-C[[:space:]]+("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)'
  HOOK_GIT_TARGETS=(); HOOK_TARGET_REASON=""
  [[ -d "$base" ]] || { HOOK_TARGET_REASON="directorio de la sesión inexistente: $base"; return 1; }
  # Cada línea es una orden: el ancla de HOOK_GIT_AT no incluye «\n» y `^` solo casa al inicio de la
  # cadena en `=~`, así que sin esto un commit en la 2.ª línea (o el 2.º de varias) no se localizaba.
  rest="${cmd//$nl/;}"
  local consumed=""
  while [[ "$rest" =~ $re_commit ]]; do
    m="${BASH_REMATCH[0]}"
    prefix="${rest%%"$m"*}"
    consumed+="$prefix"
    cwd="$base"
    # Lo que cambia el directorio o el repo sin que el análisis pueda seguirlo falla cerrado.
    if [[ "$consumed$m" =~ (^|[^[:alnum:]_])(pushd|popd)([[:space:]]|$) ]]; then
      HOOK_TARGET_REASON="pushd/popd: el directorio no se sigue"; return 1
    fi
    if [[ "$consumed$m" == *GIT_DIR=* || "$consumed$m" == *GIT_WORK_TREE=* ]]; then
      HOOK_TARGET_REASON="GIT_DIR/GIT_WORK_TREE en la orden: el árbol de trabajo no se determina"; return 1
    fi
    # Órdenes anidadas (bash -c, sh -c, eval): su contenido no se analiza, así que no se puede saber
    # en qué directorio corre el commit.
    # Solo lo anterior al commit: «eval» o «sh -c» dentro del mensaje (-m "…") no es una orden anidada.
    if [[ "$consumed$m" =~ (^|[^[:alnum:]_])((ba|z|da)?sh[[:space:]]+(-[[:alpha:]]*[[:space:]]+)*-[[:alpha:]]*c|eval)([[:space:]]|$) ]]; then
      HOOK_TARGET_REASON="orden anidada (sh -c / eval): el directorio del commit no se determina"; return 1
    fi
    # cd en segundo plano (`cd X & …`) o en tubería (`cd X | …`) corre en un subshell y no persiste.
    # Sobre prefijo + match: el match del commit se come el separador previo («& git commit»), así que
    # mirando solo el prefijo un «&&» quedaría como «&» suelto.
    local re_cd_sub='(^|[^[:alnum:]_./-])cd[[:space:]]+[^;&|]*[[:space:]]*(&[^&]|\|[^|])'
    if [[ "$consumed$m" =~ $re_cd_sub ]]; then
      HOOK_TARGET_REASON="cd en segundo plano o en tubería: no cambia el directorio del commit"; return 1
    fi
    # Lista blanca de cd: cada palabra «cd» previa tiene que ser un cd simple que el análisis sigue
    # (inicio de orden tras ; & | o salto de línea). Un cd tras {, then, do, !… no se enumera: bloquea.
    local cd_words cd_seen=0
    cd_words=$(grep -oE '(^|[^[:alnum:]_./-])cd([[:space:]]|$)' <<<"$consumed" | wc -l)
    local p="$consumed" before q1 q2
    while [[ "$p" =~ $re_cd ]]; do
      cd_seen=$((cd_seen + 1))
      if [[ "${BASH_REMATCH[1]}" == *'('* || "${BASH_REMATCH[1]}" == *'`'* ]]; then
        HOOK_TARGET_REASON="cd dentro de un subshell: no cambia el directorio del commit"; return 1
      fi
      # Un cd dentro de comillas (texto de un echo) no se ejecuta: comillas desparejadas antes de él.
      before="${p%%"${BASH_REMATCH[0]}"*}"; q1="${before//[^\"]/}"; q2="${before//[^\']/}"
      if (( ${#q1} % 2 || ${#q2} % 2 )); then
        HOOK_TARGET_REASON="cd entre comillas: no se puede saber si se ejecuta"; return 1
      fi
      if ! _hook_resolve_dir "${BASH_REMATCH[2]}" "$cwd"; then
        HOOK_TARGET_REASON="«cd ${BASH_REMATCH[2]}» no se resuelve a un directorio existente"; return 1
      fi
      cwd="$_HOOK_RESOLVED"
      p="${p#*"${BASH_REMATCH[0]}"}"
    done
    if (( cd_words > cd_seen )); then
      HOOK_TARGET_REASON="hay un cd que el análisis no sigue (tras {, then, do, !…): usa cd \"/ruta\" && git commit"; return 1
    fi
    if [[ "$m" == *--git-dir* || "$m" == *--work-tree* ]]; then
      HOOK_TARGET_REASON="--git-dir/--work-tree: el árbol de trabajo no se determina"; return 1
    fi
    p="$m"
    while [[ "$p" =~ $re_c ]]; do
      if ! _hook_resolve_dir "${BASH_REMATCH[2]}" "$cwd"; then
        HOOK_TARGET_REASON="«git -C ${BASH_REMATCH[2]}» no se resuelve a un directorio existente"; return 1
      fi
      cwd="$_HOOK_RESOLVED"
      p="${p#*"${BASH_REMATCH[0]}"}"
    done
    # Repo elegido por el texto de la orden y aún no aprobado: nada configurado por él se ejecuta.
    top=$(GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false \
          GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null GIT_OPTIONAL_LOCKS=0 \
          git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || { HOOK_TARGET_REASON="$cwd no está dentro de un repo git"; return 1; }
    top=$(cd "$top" && pwd -P)
    for t in "${HOOK_GIT_TARGETS[@]:-}"; do [[ "$t" == "$top" ]] && top=""; done
    [[ -n "$top" ]] && HOOK_GIT_TARGETS+=("$top")
    consumed+="$m"
    rest="${rest#*"$m"}"
  done
  if [[ ${#HOOK_GIT_TARGETS[@]} -eq 0 ]]; then
    HOOK_TARGET_REASON="no se localiza el «git commit» en la orden"; return 1
  fi
  return 0
}

# hook_read_posttool <hook>: entrada de un hook PostToolUse. Claude Code y OpenCode la entregan como JSON
# por stdin (tool_name, tool_input, tool_response); las variables TOOL_NAME / TOOL_INPUT / TOOL_OUTPUT /
# TOOL_DURATION solo valen de respaldo cuando stdin llega vacío o sin esos campos.
# Rellena HOOK_TOOL_NAME, HOOK_TOOL_INPUT (JSON de tool_input), HOOK_TOOL_OUTPUT (texto de la respuesta),
# HOOK_TOOL_DURATION_MS y HOOK_TOOL_STATUS (success|error). Devuelve siempre 0: un PostToolUse no bloquea.
hook_read_posttool() {
  local raw=""
  HOOK_TOOL_NAME=""; HOOK_TOOL_INPUT=""; HOOK_TOOL_OUTPUT=""; HOOK_TOOL_DURATION_MS=""; HOOK_TOOL_STATUS=""
  if [[ ! -t 0 ]]; then raw=$(timeout 3 cat 2>/dev/null || true); fi
  local trimmed="${raw#"${raw%%[![:space:]]*}"}"
  if [[ "$trimmed" == \{* ]] && command -v jq &>/dev/null && jq -e 'type == "object"' >/dev/null 2>&1 <<<"$trimmed"; then
    HOOK_TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$trimmed" 2>/dev/null) || HOOK_TOOL_NAME=""
    HOOK_TOOL_INPUT=$(jq -c '.tool_input // empty' <<<"$trimmed" 2>/dev/null) || HOOK_TOOL_INPUT=""
    HOOK_TOOL_OUTPUT=$(jq -r '
      (.tool_response // .tool_output // empty)
      | if type == "string" then .
        elif type == "object" then
          ( [ .stdout?, .stderr?, .output?, (.content? | if type == "array" then map(.text? // empty) | join("\n")
                                                         elif type == "string" then . else empty end) ]
            | map(select(type == "string" and . != "")) | join("\n") )
        else empty end' <<<"$trimmed" 2>/dev/null) || HOOK_TOOL_OUTPUT=""
    HOOK_TOOL_DURATION_MS=$(jq -r '(.tool_response? | objects | .totalDurationMs // .duration_ms // empty) // empty' <<<"$trimmed" 2>/dev/null) || HOOK_TOOL_DURATION_MS=""
    HOOK_TOOL_STATUS=$(jq -r 'if (.tool_response? | objects | .is_error // .isError // false) == true then "error" else "success" end' <<<"$trimmed" 2>/dev/null) || HOOK_TOOL_STATUS=""
  fi
  [[ -z "$HOOK_TOOL_NAME" ]] && HOOK_TOOL_NAME="${TOOL_NAME:-}"
  [[ -z "$HOOK_TOOL_INPUT" ]] && HOOK_TOOL_INPUT="${TOOL_INPUT:-}"
  [[ -z "$HOOK_TOOL_OUTPUT" ]] && HOOK_TOOL_OUTPUT="${TOOL_OUTPUT:-}"
  if [[ -z "$HOOK_TOOL_DURATION_MS" && -n "${TOOL_DURATION:-}" ]]; then
    HOOK_TOOL_DURATION_MS=$(( ${TOOL_DURATION//[^0-9]/} * 1000 )) 2>/dev/null || HOOK_TOOL_DURATION_MS=""
  fi
  [[ -z "$HOOK_TOOL_STATUS" ]] && HOOK_TOOL_STATUS="${TOOL_RESULT_STATUS:-success}"
  return 0
}
