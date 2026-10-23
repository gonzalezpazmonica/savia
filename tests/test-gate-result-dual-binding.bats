#!/usr/bin/env bats
# SE-453 S2 (DUAL_BINDING): los guards blocking dan el mismo código con la misma entrada en el hook bash
# (con y sin jq) y en su puerto nativo de OpenCode (.opencode/plugins/guards/*.ts, 2 = lanza, 0 = pasa).
# Spec: docs/specs/SE-453-gate-result-contract.spec.md (Verification protocol).
# savia-gates ejecuta los mismos .sh por su shell-bridge, así que su paridad es por construcción; el puerto
# nativo es una segunda implementación y ya divergió (git -C dir push --force y commit --amend pasaban).
# Los puertos TS no usan jq: el caso «sin jq» solo aplica al lado bash y se compara contra el mismo TS.

setup_file() {
  export NOJQ="$BATS_FILE_TMPDIR/nojq"
  mkdir -p "$NOJQ"
  local f
  for f in /usr/bin/*; do
    [[ "${f##*/}" == jq ]] && continue
    [[ -x "$f" ]] && ln -sf "$f" "$NOJQ/${f##*/}"
  done
}

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RUNNER="$REPO_ROOT/tests/fixtures/se453/ts-guard-run.ts"
  TS_RUNTIME=""
  if command -v bun >/dev/null 2>&1; then
    TS_RUNTIME="bun"
  elif [[ -x "$HOME/.bun/bin/bun" ]]; then
    TS_RUNTIME="$HOME/.bun/bin/bun"
  elif node --experimental-strip-types --no-warnings -e '' >/dev/null 2>&1; then
    TS_RUNTIME="node --experimental-strip-types --no-warnings"
  fi
  unset SAVIA_HOOK_PROFILE
}

require_ts() {
  if [[ -z "$TS_RUNTIME" && "${SAVIA_REQUIRE_TS:-}" == "1" ]]; then
    echo "SAVIA_REQUIRE_TS=1 y no hay runtime TypeScript (bun o node >= 22.6)" >&2
    return 1
  fi
  [[ -n "$TS_RUNTIME" ]] || skip "sin runtime TypeScript (bun o node >= 22.6): la paridad no se puede comprobar aquí"
}

# Código del hook bash con un PATH dado (con o sin jq).
bash_code() { # hook path command
  local json
  json=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$3")
  printf '%s' "$json" | env PATH="$2" CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR" /usr/bin/bash "$REPO_ROOT/.claude/hooks/$1.sh" >/dev/null 2>&1
  echo $?
}

# Código del puerto TS (la orden va por entorno para no escribir literales sensibles en argv).
ts_code() { # tsfile export command
  SAVIA_GUARD_CMD="$3" $TS_RUNTIME "$RUNNER" "$REPO_ROOT/.opencode/plugins/guards/$1.ts" "$2" >/dev/null 2>&1
  echo $?
}

# parity hook export expected command...: cada orden da <expected> en bash con jq, bash sin jq y TS.
parity() {
  local hook="$1" ex="$2" want="$3" c b n t fails=""
  shift 3
  for c in "$@"; do
    b=$(bash_code "$hook" "$PATH" "$c"); n=$(bash_code "$hook" "$NOJQ" "$c"); t=$(ts_code "$hook" "$ex" "$c")
    [[ "$b" == "$want" && "$n" == "$want" && "$t" == "$want" ]] || fails+="$hook [$c] bash=$b sinjq=$n ts=$t (esperado $want)"$'\n'
  done
  [[ -z "$fails" ]] || { printf '%s' "$fails" >&2; return 1; }
}

SF="-""f"
ghtoken() { printf 'ghp_%s' "$(printf 'A%.0s' $(seq 1 36))"; }
FP="--for""ce"

@test "runner: un guard que lanza da 2 y uno que no lanza da 0 (el ejecutor puede fallar)" {
  require_ts
  [ "$(ts_code block-force-push blockForcePush "git push $FP origin feat")" = 2 ]
  [ "$(ts_code block-force-push blockForcePush "ls -la")" = 0 ]
  run $TS_RUNTIME "$RUNNER" "$REPO_ROOT/.opencode/plugins/guards/block-force-push.ts" noExiste
  [ "$status" -eq 64 ]
}

@test "runner: un guard roto (lanza sin BLOCKED) da 70, no 2: no puede pasar por bloqueo" {
  require_ts
  printf '%s\n' 'export async function broken() { throw new TypeError("x is undefined"); }' > "$BATS_TEST_TMPDIR/broken.ts"
  run env SAVIA_GUARD_CMD="ls" $TS_RUNTIME "$RUNNER" "$BATS_TEST_TMPDIR/broken.ts" broken
  [ "$status" -eq 70 ]
}

@test "paridad block-credential-leak: token de GitHub ⇒ 2 en bash, bash sin jq y TS" {
  require_ts
  command -v jq >/dev/null
  parity block-credential-leak blockCredentialLeak 2 "curl -H 'Authorization: token $(ghtoken)' x" "export T=$(ghtoken)"
}

@test "paridad block-force-push: force, -C dir, amend, reset --hard y push a main ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 \
    "git push $FP origin feat" "git -C /tmp/x push $FP origin feat" "git push -f" \
    "git commit --amend -m x" "git reset --hard HEAD~1" "git push origin main" \
    "git push $FP-with-lease origin main"
}

@test "paridad block-force-push: orden en la línea 2 de un bloque multilínea ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 \
    $'cd repo\ngit push '"$FP"' origin feat' $'cd repo\ngit commit --amend -m x' \
    $'cd repo\ngit reset --hard HEAD~1' $'cd repo\ngit push origin main'
}

@test "paridad block-force-push: envuelta en bash -c, sh -c, eval, then, {, xargs ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 \
    "bash -c \"git push $FP origin feat\"" "sh -c 'git push origin main'" \
    "if true; then git push $SF; fi" "{ git push $SF; }" "eval \"git reset --hard\"" \
    "echo x | xargs git push $SF" "timeout 30 git push $FP origin feat" "! git commit --amend"
}

@test "paridad block-force-push: --force-with-lease en otra parte no exime un --force real ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 \
    "git push $FP-with-lease origin a; git push $FP origin b" \
    "git push $SF origin feat # $FP-with-lease" "git push $FP-with-lease origin HEAD:main"
}

@test "paridad sin bloqueo: inocuos, --force-with-lease a rama y mención en echo ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 0 "ls -la" "git push $FP-with-lease origin feat" \
    "git push origin main-fix" "echo 'git push $FP'" "git push $FP-with-lease origin main-fix" \
    "git commit -m 'no hagas git push $FP'" $'cd repo\ngit push origin feat' "bash -c 'git status'"
  parity block-credential-leak blockCredentialLeak 0 "ls -la" "git status"
}

@test "paridad block-infra-destructive y validate-bash-global: destructivos ⇒ 2, inocuo ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-infra-destructive blockInfraDestructive 2 "terraform destroy" "kubectl delete namespace prod"
  parity block-infra-destructive blockInfraDestructive 0 "ls -la" "terraform plan"
  parity validate-bash-global validateBashGlobal 2 "chmod 777 /etc"
  parity validate-bash-global validateBashGlobal 0 "ls -la"
}
