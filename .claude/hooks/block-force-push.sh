#!/bin/bash
set -uo pipefail
# block-force-push.sh — Bloquea git push --force y commits directos a main
# Usado por: commit-guardian (PreToolUse hook)
# Profile tier: security

LIB_DIR="$(dirname "${BASH_SOURCE[0]}")/lib"
if [[ -f "$LIB_DIR/profile-gate.sh" ]]; then
  # shellcheck source=/dev/null
  source "$LIB_DIR/profile-gate.sh" && profile_gate "security"
fi

# Read stdin with timeout to avoid hanging if no input arrives
# Uses timeout+cat to handle input that may lack trailing newline
INPUT=""
if INPUT=$(timeout 3 cat 2>/dev/null); then
  :
fi

# SE-453 S2: sin jq se degrada a un parseo con grep; si tampoco se puede evaluar, sale 2 (nunca 0 sin evaluar).
# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-input.sh"
hook_extract_command "$INPUT" || exit 2
COMMAND="$HOOK_COMMAND"

if [ -z "$COMMAND" ]; then
  exit 0
fi

# Inicio de una orden git real: al principio de una línea, tras un separador, al abrir un subshell o
# dentro de `bash -c "…"`/`bash -lc`/`sh -c '…'`/`eval`, con lo que puede ir delante (VAR=valor, los
# envoltorios env, command, sudo, doas, nohup, time, exec, xargs, nice, ionice, stdbuf, setsid y timeout con
# sus opciones —`sudo -u x`, `env -i`, `timeout -s KILL 30`—, then, do, if, !, {), una ruta o una barra
# invertida delante de git (`/usr/bin/git`, `\git`) y opciones globales de git (-C dir, -c clave=valor,
# --no-pager…). Una mención dentro de un mensaje o de un echo no casa.
# grep evalúa línea a línea: una orden en la línea 2 de un bloque multilínea también casa (SE-453).
# El puerto TS (.opencode/plugins/guards/block-force-push.ts) lleva la misma gramática con el flag m, escrita
# sin ambigüedades para que V8 no se cuelgue en vueltas atrás (grep no tiene ese problema).
GIT_AT='(^|[;&|(`]|\$\(|\b((ba|z|da|k)?sh([[:space:]]+-[A-Za-z]+)*[[:space:]]+-[A-Za-z]*c|eval)[[:space:]]+["'"'"']?)[[:space:]]*(([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*|(env|command|sudo|doas|nohup|time|exec|xargs|nice|ionice|stdbuf|setsid|timeout)([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*|timeout[[:space:]]+[^[:space:]]+|[0-9][0-9.]*[smhd]?|then|do|else|if|elif|while|until|!|\{)[[:space:]]+)*(\\|[^[:space:]]*/)?git(([[:space:]]+(-C|-c|--git-dir|--work-tree)[[:space:]]+(\"[^\"]*\"|'"'"'[^'"'"']*'"'"'|[^-[:space:]][^[:space:]]*))|([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?))*[[:space:]]+'
# Fin de una opción o de un nombre de rama: espacio, fin de línea, separador o cierre de comillas.
END='([[:space:]]|$|[;&|)"'"'"'`])'
# main/master como destino de un push de esta misma orden (sin cruzar ;, & ni |): palabra suelta o tras
# `:` o `+` de un refspec, o tras refs/heads/ o refs/remotes/<remoto>/ (`HEAD:main`, `+main`,
# `refs/heads/main`, `main:main`); `main-fix` y `feature/main` no casan.
PUSH_MAIN='push[[:space:]]+([^;&|]*([[:space:]:+"'"'"']|refs/heads/|refs/remotes/[^/[:space:]]+/))?(main|master)([[:space:]:]|$|[;&|)"'"'"'`])'
# main/master como destino: palabra suelta o tras `:`, `+` o `/` de un refspec; `main-fix` no casa.
MAIN_REF='(^|[[:space:]:+"'"'"']|refs/heads/|refs/remotes/[^/[:space:]]+/)(main|master)([[:space:]:;&|)"'"'"'`]|$)'

# Bloquear force push (permite --force-with-lease en ramas no-main)
# --force-with-lease es más seguro: falla si el remoto avanzó sin nuestro conocimiento.
# Requerido en flujo de rebase de PRs en cola (SPEC-105).
IS_FORCE_WITH_LEASE=no
IS_BARE_FORCE=no
IS_PUSH_TO_MAIN=no

if echo "$COMMAND" | grep -iE "${GIT_AT}push[[:space:]]+.*--force-with-lease" > /dev/null; then
  IS_FORCE_WITH_LEASE=yes
fi
if echo "$COMMAND" | grep -iE "${GIT_AT}push[[:space:]]+([^;&|]*[[:space:]])?((--force|-f)${END}|[\"']?\+[^[:space:]])" > /dev/null; then
  IS_BARE_FORCE=yes
fi
if echo "$COMMAND" | grep -iE "git[[:space:]]+push[[:space:]]+.*${MAIN_REF}" > /dev/null; then
  IS_PUSH_TO_MAIN=yes
fi

# Bare --force (o refspec `+rama`, que fuerza igual) siempre bloqueado, aunque otra parte de la orden lleve --force-with-lease (SE-453):
# la regex de force no casa con --force-with-lease, así que un yes aquí es un --force/-f real.
if [[ "$IS_BARE_FORCE" == "yes" ]]; then
  echo "BLOQUEADO: git push --force no está permitido. Usa --force-with-lease." >&2
  exit 2
fi

# --force-with-lease a main/master bloqueado (solo permitido en ramas feature)
if [[ "$IS_FORCE_WITH_LEASE" == "yes" && "$IS_PUSH_TO_MAIN" == "yes" ]]; then
  echo "BLOQUEADO: --force-with-lease a main/master no permitido." >&2
  exit 2
fi

# Bloquear push directo a main/master
# FIX: Add anchoring for compound command separators
if echo "$COMMAND" | grep -iE "${GIT_AT}${PUSH_MAIN}" > /dev/null; then
  echo "BLOQUEADO: Push directo a main/master no permitido. Usa rama + PR." >&2
  exit 2
fi

# Bloquear commit --amend sin confirmación explícita
# FIX: Add anchoring for compound command separators
if echo "$COMMAND" | grep -iE "${GIT_AT}commit[[:space:]]+.*--amend" > /dev/null; then
  echo "BLOQUEADO: git commit --amend puede destruir commits anteriores. Crea un commit nuevo." >&2
  exit 2
fi

# Bloquear reset --hard
# FIX: Add anchoring for compound command separators
if echo "$COMMAND" | grep -iE "${GIT_AT}reset[[:space:]]+--hard" > /dev/null; then
  echo "BLOQUEADO: git reset --hard puede perder trabajo. Usa git stash o git revert." >&2
  exit 2
fi

exit 0
