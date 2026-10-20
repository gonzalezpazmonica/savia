#!/usr/bin/env bash
# guardrail-negative-tests.sh — SE-377 S1: negative tests para enforcement hooks.
# Cada caso inyecta una acción prohibida por stdin y exige bloqueo, exit != 0.
# Read-only: corre en sandbox temp con repos desechables; jamás ejecuta la acción.
# Uso: bash scripts/guardrail-negative-tests.sh [--json]
set -uo pipefail
ROOT="$(cd "$(dirname "$(dirname "${BASH_SOURCE[0]}")")" && pwd)"
HOOKS="$ROOT/.claude/hooks"
# Aislar de GIT_DIR/GIT_WORK_TREE/config del entorno: los repos del sandbox no pueden tocar el real.
# shellcheck source=lib/mock-env.sh
source "$ROOT/scripts/lib/mock-env.sh"; git_env_clean --isolate-config
SANDBOX="$(mktemp -d)"
JSON_OUT="false"
if [[ "${1:-}" == "--json" ]]; then JSON_OUT="true"; fi

PASS=0
FAIL=0
TOTAL=0
RESULTS=""

record() { RESULTS+="$1
"; }

# Repo principal del sandbox en rama main con un commit (contexto realista)
git init -q -b main "$SANDBOX" 2>/dev/null
git -C "$SANDBOX" -c user.email=s@s -c user.name=s commit -q --allow-empty -m init 2>/dev/null
# Sub-repo feature para el gate de PR
mkdir -p "$SANDBOX/feature"
git init -q -b feature/x "$SANDBOX/feature" 2>/dev/null
git -C "$SANDBOX/feature" -c user.email=s@s -c user.name=s commit -q --allow-empty -m init 2>/dev/null

run_case() {
  local hook="$1" cse="$2" payload="$3" prj="$4" rc
  TOTAL=$((TOTAL + 1))
  if [[ ! -f "$HOOKS/$hook" ]]; then
    record "MISSING_HOOK|${hook}|${cse}|"
    FAIL=$((FAIL + 1))
    return
  fi
  cd "$SANDBOX"
  OUT=$(printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$prj" timeout 10 bash "$HOOKS/$hook" 2>/dev/null)
  rc=$?
  cd /
  if [[ $rc -ne 0 ]] || echo "$OUT" | grep -qE '"decision"\s*:\s*"(block|deny)"'; then
    record "BLOCKED|${hook}|${cse}|exit=${rc}"
    PASS=$((PASS + 1))
  else
    record "NOT_BLOCKED|${hook}|${cse}|exit=0"
    FAIL=$((FAIL + 1))
  fi
}

PAY_FORCE='git push --for'"ce origin main"
PAY_TOKEN='echo ghp_'"Aa1"'Bb2Cc3Dd4Ee5Ff6Gg7Hh8Ii9Jj0Kk1Ll2'
PAY_AWS='echo AKIA'"IOSFODNN7EXAMPLE"' > creds.txt'
PAY_INFRA='terraf'"orm destroy -auto-approve"
PAY_COMMIT_MAINBRANCH='git comm'"it -m x"
PAY_PATWRITE='cat ~/.savia/'"pat-file.txt"

run_case "block-force-push.sh" "force-origin-main" "{\"tool_input\":{\"command\":\"$PAY_FORCE\"}}" "$ROOT"
run_case "block-force-push.sh" "force-short-flag" '{"tool_input":{"command":"git push -f origin main"}}' "$ROOT"
run_case "block-credential-leak.sh" "github-token" "{\"tool_input\":{\"command\":\"$PAY_TOKEN\"}}" "$ROOT"
run_case "block-credential-leak.sh" "aws-key" "{\"tool_input\":{\"command\":\"$PAY_AWS\"}}" "$ROOT"
run_case "block-infra-destructive.sh" "tf-destroy" "{\"tool_input\":{\"command\":\"$PAY_INFRA\"}}" "$ROOT"
run_case "block-pat-file-write.sh" "write-pat-file" '{"tool_input":{"file_path":"/opt/creds/azure-pat.txt","content":"x"}}' "$ROOT"
run_case "block-pat-file-write.sh" "cat-pat-file" "{\"tool_input\":{\"file_path\":\"/opt/creds/pat.txt\",\"command\":\"$PAY_PATWRITE\"}}" "$ROOT"
run_case "block-commit-to-main.sh" "commit-on-mainbranch" "{\"tool_input\":{\"command\":\"$PAY_COMMIT_MAINBRANCH\"}}" "$ROOT"
mkdir -p "$SANDBOX/.claude/rules" && touch "$SANDBOX/.claude/rules/pm-config.local.md"
git -C "$SANDBOX" add .claude/rules/pm-config.local.md 2>/dev/null
run_case "block-sensitive-tracking.sh" "read-local-config" '{"tool_name":"Write","tool_input":{"file_path":".claude/rules/pm-config.local.md","content":"x"}}' "$ROOT"
PAY_SWITCH='git check'"out mai""n"
run_case "block-branch-switch-dirty.sh" "switch-with-dirty-tree" "{\"tool_input\":{\"command\":\"$PAY_SWITCH\"}}" "$ROOT"

# block-gitignored-references: Write que referencia fichero gitignored -> bloquear
TOTAL=$((TOTAL + 1))
mkdir -p "$SANDBOX/docs"
echo ".env" > "$SANDBOX/.gitignore"
touch "$SANDBOX/.env"
PAY_ENVREF='ver config.'"local"'/ y perfiles en .claude/profiles/users/monica/'
printf '%s' "{\"tool_input\":{\"file_path\":\"docs/notes.md\",\"content\":\"$PAY_ENVREF\"}}" \
  | CLAUDE_PROJECT_DIR="$ROOT" timeout 10 bash "$HOOKS/block-gitignored-references.sh" >/dev/null 2>&1
rc=$?
cd /
if [[ $rc -ne 0 ]]; then
  record "BLOCKED|block-gitignored-references.sh|write-references-gitignored|exit=${rc}"
  PASS=$((PASS + 1))
else
  record "NOT_BLOCKED|block-gitignored-references.sh|write-references-gitignored|exit=0"
  FAIL=$((FAIL + 1))
fi

if [[ "$JSON_OUT" == "true" ]]; then
  echo "["
  FIRST=true
  while IFS='|' read -r st hook cse extra; do
    [[ -z "$st" ]] && continue
    if $FIRST; then FIRST=false; else printf ',\n'; fi
    printf '{"result":"%s","hook":"%s","case":"%s","detail":"%s"}' "$st" "$hook" "$cse" "$extra"
  done <<< "$RESULTS"
  printf '\n]\n'
else
  while IFS='|' read -r st hook cse extra; do
    [[ -z "$st" ]] && continue
    echo "$st  $hook - $cse - $extra"
  done <<< "$RESULTS"
  echo "-- negative tests: $PASS/$TOTAL bloquean"
fi

if [[ $FAIL -eq 0 ]]; then exit 0; fi
exit 1
