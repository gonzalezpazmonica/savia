#!/usr/bin/env bash
# run-chaos-suite.sh — SE-383: suite adversarial/chaos para hooks y gates.
# Sandbox hermético: temp dirs, sin red, perturbaciones sobre hooks REALES
# en copias desechables. Seed determinista. Nunca toca el repo real.
# Salida: lista de escenarios PASS/FAIL + resumen. Exit 1 si algún FAIL.
set -uo pipefail
ROOT="$(cd "$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")" && pwd)"
HOOKS="$ROOT/.claude/hooks"
PASS=0; FAIL=0; RESULTS=""

record() { RESULTS+="$1
"; }

aggregate_verdict() {
  local pass_count="$1" fail_count="$2"
  echo "-- chaos suite: $pass_count PASS / $fail_count FAIL-RED"
  [[ "$fail_count" -eq 0 && "$pass_count" -gt 0 ]]
}

if [[ "${1:-}" == "--aggregate" ]]; then
  if [[ $# -ne 3 ]] || ! [[ "$2" =~ ^[0-9]+$ && "$3" =~ ^[0-9]+$ ]]; then
    echo "usage: $0 --aggregate PASS_COUNT FAIL_COUNT" >&2
    exit 2
  fi
  aggregate_verdict "$2" "$3"
  exit $?
fi

assert_clean_exit() { # nombre, exit_code, stdout, condiciones: no traceback, exit en {0,1,2}
  local name="$1" rc="$2" out="$3"
  if [[ $rc -gt 2 ]] || echo "$out" | grep -qiE "traceback|syntax error|bad substitution|unbound variable"; then
    record "FAIL|$name|rc=$rc ${out:0:60}"
    FAIL=$((FAIL+1))
  else
    record "PASS|$name|rc=$rc"
    PASS=$((PASS+1))
  fi
}

S=$(mktemp -d)
# P1 — cwd inexistente: el hook no debe colgarse ni reventar
PAY1='{"tool_input":{"command":"git push -f origin whatever"}}'
( cd "$S" && printf '%s' "$PAY1" | CLAUDE_PROJECT_DIR="$S/nonexistent_dir_xyz" timeout 10 bash "$HOOKS/block-force-push.sh" >/dev/null 2>&1 )
assert_clean_exit "P1-cwd-inexistente" $? ""

# P2 — stdin JSON corrupto
( printf '%s' '{"tool_input":{"command": GARBAGE}}' | timeout 10 bash "$HOOKS/block-force-push.sh" >/dev/null 2>&1 )
assert_clean_exit "P2-json-corrupto" $? ""

# P3 — stdin JSON vacío (sin campos)
( printf '%s' '{}' | timeout 10 bash "$HOOKS/block-commit-to-main.sh" >/dev/null 2>&1 )
assert_clean_exit "P3-json-vacio" $? ""

# P4 — paths con espacios (payload de escritura a ruta con espacios)
PAY4="{\"tool_input\":{\"file_path\":\"/tmp/dir con espacios/azure-pat.txt\",\"content\":\"x\"}}"
( cd "$S" && printf '%s' "$PAY4" | timeout 10 bash "$HOOKS/block-pat-file-write.sh" >/dev/null 2>&1 )
assert_clean_exit "P4-path-con-espacios" $? ""

# P5 — variable sin expandir dentro del command
PAY5='{\"tool_input\":{\"command\":\"echo \$HOME/secret\"}}'
( cd "$S" && printf '%s' "$PAY5" | timeout 10 bash "$HOOKS/block-credential-leak.sh" >/dev/null 2>&1 )
assert_clean_exit "P5-variable-sin-expandir" $? ""

# P6 — hook sin permisos de ejecución + dependencia ausente (jq no disponible)
S6=$(mktemp -d); cp "$HOOKS/block-force-push.sh" "$S6/h.sh"; chmod -x "$S6/h.sh"
PATH_SAVED="$PATH"
( cd "$S6" && printf '%s' "$PAY1" | timeout 10 bash "$S6/h.sh" >/dev/null 2>&1 )
assert_clean_exit "P6-no-ejecutable" $? ""
mkdir -p "$S6/nojq"
( cd "$S6" && printf '%s' "$PAY1" | PATH="$S6/nojq:/usr/bin:/bin" timeout 10 bash "$HOOKS/block-force-push.sh" >/dev/null 2>&1 )
assert_clean_exit "P7-dependencia-ausente-sin-jq" $? ""

# P8 — fixture fundador SE-383 (RESUELTO): hooks worktree-aware.
# Historia: el hook bloqueó commits legítimos en worktrees (incidente 2026-09-05).
# Fix: validate-bash-global.sh captura ENTRY_PWD antes de las libs (PR p8-curation).
make_payload() { printf '{"tool_input":{"command":"%s commit -m x"}}' 'git'; }
WT=$(mktemp -d)
git -C "$ROOT" worktree add "$WT" -b "chaos-p8-$(basename "$WT")" origin/main >/dev/null 2>&1
( cd "$WT" && printf '%s' "$(make_payload)" | CLAUDE_PROJECT_DIR="$ROOT" timeout 10 bash "$ROOT/.claude/hooks/validate-bash-global.sh" >/dev/null 2>&1 )
P8WT=$?
( cd "$ROOT" && printf '%s' "$(make_payload)" | CLAUDE_PROJECT_DIR="$ROOT" timeout 10 bash "$ROOT/.claude/hooks/validate-bash-global.sh" >/dev/null 2>&1 )
P8MAIN=$?
git -C "$ROOT" worktree remove "$WT" --force >/dev/null 2>&1
git -C "$ROOT" branch -D "chaos-p8-$(basename "$WT")" >/dev/null 2>&1 || true
CUR_BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
if [[ "$CUR_BRANCH" == "main" || "$CUR_BRANCH" == "master" ]]; then
  if [[ $P8WT -eq 0 && $P8MAIN -eq 2 ]]; then
    record "PASS|P8-worktree-aware-guard|worktree permite, main bloquea"
    PASS=$((PASS+1))
  else
    record "FAIL|P8-worktree-aware-guard|wt=$P8WT main=$P8MAIN"
    FAIL=$((FAIL+1))
  fi
else
  if [[ $P8WT -eq 0 ]]; then
    record "PASS|P8-worktree-aware-guard|worktree permite (caso main N/A en rama $CUR_BRANCH)"
    PASS=$((PASS+1))
  else
    record "FAIL|P8-worktree-aware-guard|wt=$P8WT"
    FAIL=$((FAIL+1))
  fi
fi

rm -rf "$S" "$S6"
echo "$RESULTS"
aggregate_verdict "$PASS" "$FAIL"
exit $?
