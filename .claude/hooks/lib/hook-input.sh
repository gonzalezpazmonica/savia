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

# hook_strip_file_heredocs <orden>: quita los cuerpos de heredoc que solo escriben un fichero
# (`cat > f <<'EOF'`, `tee f <<EOF`); su texto no se ejecuta y no es un commit. Los demás heredocs
# (`bash <<EOF`, `python - <<EOF`) se conservan. Resultado por stdout.
hook_strip_file_heredocs() {
  printf '%s\n' "$1" | awk '
    skip != "" { if ($0 ~ "^[[:space:]]*" skip "[[:space:]]*$") skip = ""; next }
    {
      print
      if ($0 ~ /^[[:space:]]*(cat|tee)([[:space:]]|$)/ && match($0, /<<-?[[:space:]]*["\x27]?[A-Za-z_][A-Za-z0-9_]*["\x27]?/)) {
        tag = substr($0, RSTART, RLENGTH); sub(/^<<-?[[:space:]]*["\x27]?/, "", tag); sub(/["\x27]$/, "", tag)
        skip = tag
      }
    }'
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
  rest="$cmd"
  local consumed=""
  while [[ "$rest" =~ $re_commit ]]; do
    m="${BASH_REMATCH[0]}"
    prefix="${rest%%"$m"*}"
    consumed+="$prefix"
    cwd="$base"
    local p="$consumed"
    while [[ "$p" =~ $re_cd ]]; do
      if ! _hook_resolve_dir "${BASH_REMATCH[2]}" "$cwd"; then
        HOOK_TARGET_REASON="«cd ${BASH_REMATCH[2]}» no se resuelve a un directorio existente"; return 1
      fi
      cwd="$_HOOK_RESOLVED"
      p="${p#*"${BASH_REMATCH[0]}"}"
    done
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
    top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || { HOOK_TARGET_REASON="$cwd no está dentro de un repo git"; return 1; }
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
