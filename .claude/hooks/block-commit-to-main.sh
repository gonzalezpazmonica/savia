#!/usr/bin/env bash
set -uo pipefail
# Drain the hook JSON from stdin (unread input can break the harness pipe).
[[ -t 0 ]] || INPUT=$(timeout 3 cat 2>/dev/null) || true
# block-commit-to-main.sh — SE-337: bloquea `git commit` en ramas humanas.
#
# autonomous-safety: NUNCA commit en ramas de humanos (main, develop,
# feature/* humano). Este guard lo mecaniza: si branch ∈ {main, master},
# bloquea el commit con JSON decision:block. Bypass consciente SOLO para
# la operadora: SAVIA_ALLOW_MAIN_COMMIT=1 (con registro en JSONL, RN-04).
#
# PreToolUse Bash(git commit*). PURE_BASH, sin red (CRIT-001).

# Some frontends register this hook for every Bash invocation. Filter the
# command here too; unknown payloads retain the conservative branch check.
if COMMAND=$(printf '%s' "${INPUT:-}" | jq -er '
  (.tool_input.command // .tool_input.cmd)
  | select(type == "string" and length > 0)
' 2>/dev/null); then
  GIT_TOKEN='(^|[^[:alnum:]_])git([^[:alnum:]_]|$)'
  # A subcommand is a shell word; --no-commit and commit-msg are not commits.
  COMMIT_TOKEN="(^|[[:space:];|&()\"'])commit([[:space:];|&()\"']|$)"
  if ! [[ "$COMMAND" =~ $GIT_TOKEN ]] || ! [[ "$COMMAND" =~ $COMMIT_TOKEN ]]; then
    exit 0
  fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="${SAVIA_TURN_SDLC_LOG_DIR:-$ROOT/output/turn-sdlc}"

# Rama de un directorio ("" si no es un repo o HEAD está separado).
branch_of() {
  git -C "$1" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  git -C "$1" branch --show-current 2>/dev/null || true
}
is_human() { [[ "$1" == "main" || "$1" == "master" ]]; }

BASE_DIR=$(printf '%s' "${INPUT:-}" | jq -r '
  (.tool_input.workdir // .cwd // empty) | select(type == "string")
' 2>/dev/null) || BASE_DIR=""
BASE_DIR="${BASE_DIR:-$PWD}"

# El repo que importa es el DESTINO de cada `git commit` real, no el checkout
# de la sesión: lo resuelve scripts/lib/git_op_targets.py (git -C, cd
# encadenado, variables literales; heredocs y cadenas son texto). Destino no
# resoluble o fuera de un repo → cwd de la orden (conservador). Sin Python o
# sin orden legible → comportamiento anterior.
BRANCH=""
RESOLVER="$ROOT/scripts/lib/git_op_targets.py"
if [[ -n "${COMMAND:-}" ]] && command -v python3 >/dev/null 2>&1 \
   && TARGETS=$(printf '%s' "$COMMAND" | timeout 5 python3 "$RESOLVER" "$BASE_DIR" 2>/dev/null); then
  while IFS=$'\t' read -r op dir; do
    [[ "$op" == "commit" ]] || continue
    if [[ -n "$dir" ]] && git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      b=$(branch_of "$dir")
    else
      b=$(branch_of "$BASE_DIR")
    fi
    if is_human "$b"; then BRANCH="$b"; break; fi
  done <<< "$TARGETS"
else
  TARGET_DIR="$BASE_DIR"
  # Forma explícita `cd "<ruta>" && git commit` (un cd fallido no ejecuta el git).
  CD_PREFIX='^[[:space:]]*cd[[:space:]]+"([^"]+)"[[:space:]]*&&[[:space:]]*git[[:space:]]+commit([[:space:]]|$)'
  if [[ "${COMMAND:-}" =~ $CD_PREFIX ]]; then
    COMMAND_DIR="${BASH_REMATCH[1]}"
    if [[ "$COMMAND_DIR" == /* ]]; then
      TARGET_DIR="$COMMAND_DIR"
    else
      TARGET_DIR="$TARGET_DIR/$COMMAND_DIR"
    fi
  fi
  BRANCH=$(branch_of "$TARGET_DIR")
fi
# vacío (detached/recién init/rama segura) → no proteger
[[ -z "$BRANCH" ]] && exit 0

# Solo proteger ramas de humano: main y master
if [[ "$BRANCH" != "main" && "$BRANCH" != "master" ]]; then
  exit 0
fi

# Bypass consciente de la operadora (se registra, no es silencioso)
if [[ "${SAVIA_ALLOW_MAIN_COMMIT:-0}" == "1" ]]; then
  mkdir -p "$LOG_DIR"
  printf '{"ts":"%s","branch":"%s","action":"commit","verdict":"bypass","env":"SAVIA_ALLOW_MAIN_COMMIT=1"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BRANCH" >> "$LOG_DIR/commit-guard.jsonl" 2>/dev/null || true
  exit 0
fi

# Bloqueo
mkdir -p "$LOG_DIR"
printf '{"ts":"%s","branch":"%s","action":"commit","verdict":"block"}\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$BRANCH" >> "$LOG_DIR/commit-guard.jsonl" 2>/dev/null || true

REASON="Commit en rama humana ($BRANCH) bloqueado por autonomous-safety (regla: NUNCA commit en main/master). Crea una rama agent/* propia y commitea ahí: git checkout -b agent/<tarea>. Si Eres la operadora y el commit en main es intencional, repitelo con SAVIA_ALLOW_MAIN_COMMIT=1 (queda registrado)."

if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$REASON" '{decision: "block", reason: $r}'
else
  printf '{"decision":"block","reason":"%s"}\n' "$REASON"
fi
exit 0
