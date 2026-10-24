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
    # Con `&&` como última orden del bucle, un último /usr/bin/* no ejecutable hacía fallar setup_file.
    if [[ -x "$f" ]]; then ln -sf "$f" "$NOJQ/${f##*/}"; fi
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
  elif node --experimental-strip-types --no-warnings -e 'await import(process.argv[1])' "$REPO_ROOT/.opencode/plugins/guards/block-force-push.ts" >/dev/null 2>&1; then
    TS_RUNTIME="node --experimental-strip-types --no-warnings"
  fi
  unset SAVIA_HOOK_PROFILE
}

require_ts() {
  if [[ -z "$TS_RUNTIME" && "${SAVIA_REQUIRE_TS:-}" == "1" ]]; then
    echo "SAVIA_REQUIRE_TS=1 y no hay runtime TypeScript (bun o node >= 22.7)" >&2
    return 1
  fi
  [[ -n "$TS_RUNTIME" ]] || skip "sin runtime TypeScript (bun o node >= 22.7): la paridad no se puede comprobar aquí"
  require_jq
}

# La paridad compara bash con jq y sin jq: hace falta jq en PATH y que $NOJQ lo oculte de verdad
# (si jq viviera en /usr/bin/jq y el filtro fallara, «sin jq» sería otra vez «con jq» sin que se notara).
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    [[ "${SAVIA_REQUIRE_TS:-}" == "1" ]] && { echo "SAVIA_REQUIRE_TS=1 y no hay jq" >&2; return 1; }
    skip "sin jq: el lado «con jq» de la paridad no se puede comprobar aquí"
  fi
  if env PATH="$NOJQ" /usr/bin/bash -c 'command -v jq' >/dev/null 2>&1; then
    echo "el PATH sin jq ($NOJQ) todavía resuelve jq" >&2
    return 1
  fi
}

# Código del hook bash con un PATH dado (con o sin jq). Un 2 sin «BLOQUEADO» en stderr no es un bloqueo
# de la regla sino una orden inevaluable (`hook_extract_command || exit 2`): sale «2-sin-bloqueo».
bash_code() { # hook path command
  local json err rc
  json=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$3")
  err=$(printf '%s' "$json" | env PATH="$2" CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR" /usr/bin/bash "$REPO_ROOT/.claude/hooks/$1.sh" 2>&1 >/dev/null)
  rc=$?
  if [[ "$rc" -eq 2 && "$err" != *BLOQUEADO* ]]; then echo "2-sin-bloqueo"; else echo "$rc"; fi
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
SU="su""do"
rep() { local i out=""; for ((i = 0; i < $2; i++)); do out+="$1"; done; printf '%s' "$out"; } # rep texto n

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
  parity block-credential-leak blockCredentialLeak 2 "curl -H 'Authorization: token $(ghtoken)' x" "export T=$(ghtoken)"
}

@test "paridad block-force-push: force, -C dir, amend, reset --hard y push a main ⇒ 2" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "git push $FP origin feat" "git -C /tmp/x push $FP origin feat" "git push -f" \
    "git commit --amend -m x" "git reset --hard HEAD~1" "git push origin main" \
    "git push $FP-with-lease origin main"
}

@test "paridad block-force-push: orden en la línea 2 de un bloque multilínea ⇒ 2" {
  require_ts
  parity block-force-push blockForcePush 2 \
    $'cd repo\ngit push '"$FP"' origin feat' $'cd repo\ngit commit --amend -m x' \
    $'cd repo\ngit reset --hard HEAD~1' $'cd repo\ngit push origin main'
}

@test "paridad block-force-push: envuelta en bash -c, sh -c, eval, then, {, xargs ⇒ 2" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "bash -c \"git push $FP origin feat\"" "sh -c 'git push origin main'" \
    "if true; then git push $SF; fi" "{ git push $SF; }" "eval \"git reset --hard\"" \
    "echo x | xargs git push $SF" "timeout 30 git push $FP origin feat" "! git commit --amend"
}

@test "paridad block-force-push: --force-with-lease en otra parte no exime un --force real ⇒ 2" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "git push $FP-with-lease origin a; git push $FP origin b" \
    "git push $SF origin feat # $FP-with-lease" "git push $FP-with-lease origin HEAD:main"
}

@test "paridad block-force-push: git con ruta o \\git y envoltorios con opciones ⇒ 2 (revisión #1348 P1-1)" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "/usr/bin/git push $FP origin feat" '\git push '"$FP"' origin feat' "cd x && /usr/bin/git reset --hard" \
    "$SU -u bot git push $FP origin feat" "env -i git push $SF" "nice -n 5 git push $SF" \
    "time -p git reset --hard" "timeout -s KILL 5 git push $SF" "echo x | xargs -n1 git push $SF" \
    "doas git push $SF" "bash -lc 'git push $SF'" "bash -l -c 'git push $SF'"
}

@test "paridad block-force-push: main:main, rama entre comillas con lease y refspec +rama ⇒ 2 (P1-1, P1-2, P2-1)" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "git push origin main:main" "git push origin HEAD:refs/heads/main" "git push origin HEAD:main" \
    "git push $FP-with-lease origin 'main'" "git push $FP-with-lease origin \"main\"" \
    "git push $FP-with-lease origin \"master\"" "git push origin \"main\"" "git push origin 'main'" \
    "git push origin +feat" "git push origin '+feat'" "git push origin +main"
}

# Revisión de seguridad de a71007ba9, P1-1: en `main` el TS sin ancla bloqueaba estas formas; con GIT_AT
# dejaron de bloquear en OpenCode. `su -c`, `-exec` de find y `strace`/`ltrace`/`ssh <host>` son inicio de orden
# o envoltorio en los dos bindings. P2-1: las banderas cortas combinadas (`-fu`, `-uf`) fuerzan igual.
@test "paridad block-force-push: su -c, find -exec, strace, ltrace, ssh y -fu ⇒ 2 (revisión #1348 seguridad P1-1, P2-1)" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "su -c 'git push $FP origin feat'" "su - bot -c 'git push $FP origin feat'" "su -l bot -c 'git reset --hard'" \
    "su -c 'git push origin main'" "su bot -c \"git commit --amend\"" \
    "find . -exec git push $FP origin feat \\;" "find . -execdir git reset --hard \\;" \
    "strace -f git push $SF" "ltrace git push $FP origin feat" "ssh host git push $FP origin feat" \
    "ssh -p 22 user@host git reset --hard" "ssh host 'git push $SF'" \
    "git push -fu origin feat" "git push -uf origin feat"
}

# Límite declarado (no se arregla aquí): una orden git dentro de una cadena de otro intérprete no casa.
@test "paridad límite: git dentro de python3 -c no bloquea en ninguno de los dos (límite declarado)" {
  require_ts
  parity block-force-push blockForcePush 0 \
    "python3 -c \"import os; os.system('git push $FP')\""
}

# Límite conocido, igual en los dos lados: tras `eval` o `sh -c` no se distingue una orden real de prosa
# dentro de un echo, así que bloquea (falso positivo aceptado, como `--amend` en un mensaje). Si un día se
# afina, este test tiene que cambiar a 0 en bash y en TS a la vez.
@test "paridad límite: eval o sh -c dentro de un echo bloquea en bash y en TS (falso positivo documentado)" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "echo \"ejemplo: eval git push $SF\"" "echo 'usa sh -c \"git reset --hard\"'"
}

@test "paridad sin bloqueo: inocuos, --force-with-lease a rama y mención en echo ⇒ 0" {
  require_ts
  parity block-force-push blockForcePush 0 "ls -la" "git push $FP-with-lease origin feat" \
    "git push origin main-fix" "echo 'git push $FP'" "git push $FP-with-lease origin main-fix" \
    "git commit -m 'no hagas git push $FP'" $'cd repo\ngit push origin feat' "bash -c 'git status'" \
    "git push origin feat-main" "git push origin main-fix:main-fix" "nice -n 5 git status" \
    "/usr/bin/git push -u origin feat" "$SU -u bot git push origin feat" "sleep 5 && git status" \
    "echo \"no hagas git push $FP\"" "git push origin \"main-fix\"" "git push origin feature/main" "git push -u origin release/master" "git push $FP-with-lease origin feature/main" \
    "git push -u origin feat" "git push --follow-tags origin feat" "su -c 'git status'" "ssh host git status" \
    "find . -exec git status \\;" "strace -f git push origin feat" "git push -uq origin feat"
  parity block-credential-leak blockCredentialLeak 0 "ls -la" "git status"
}

@test "paridad: ninguna regla cruza un salto de línea (grep evalúa línea a línea; TS igual)" {
  require_ts
  parity block-force-push blockForcePush 0 \
    $'git push origin feat\nmain' $'git push origin feat\n'"$SF" $'git push\n'"$FP"
}

# Con 30 repeticiones una gramática ambigua son ~2^30 vueltas atrás (minutos); sin ambigüedad, milisegundos.
@test "TS sin vueltas atrás exponenciales: entradas ambiguas terminan en < 1 s (revisión #1348 P2-1)" {
  require_ts
  local c err ms
  # Se mide solo la llamada al guard (SAVIA_GUARD_TIME=1 la imprime), no el arranque en frío del runtime:
  # en un runner de CI cargado el arranque de bun/node podía pasar de 1 s sin que la regex tuviera culpa.
  for c in "git$(rep ' -c -a' 30)" "git$(rep ' -C -C' 30) !" "nice$(rep ' -n 5' 30)" "$SU$(rep ' -u env' 30)" \
    "timeout$(rep ' -k timeout' 30)" "su$(rep ' -c' 30) x" "su$(rep ' - -c' 30) x" "ssh$(rep ' -o x' 30) !" \
    "find$(rep ' -exec' 30) !" "git push -$(rep 'f' 3000)1"; do
    err=$(timeout 20 env SAVIA_GUARD_CMD="$c" SAVIA_GUARD_TIME=1 $TS_RUNTIME "$RUNNER" "$REPO_ROOT/.opencode/plugins/guards/block-force-push.ts" blockForcePush 2>&1 >/dev/null; echo "rc=$?")
    [[ "$err" == *"rc=0" ]] || { echo "rc inesperado: $err (${c:0:40}…)" >&2; return 1; }
    ms=$(sed -n 's/^guard-ms=\([0-9]*\).*/\1/p' <<<"$err")
    [[ -n "$ms" ]] || { echo "el runner no midió el guard: $err" >&2; return 1; }
    (( ms < 1000 )) || { echo "tarda $ms ms: ${c:0:40}…" >&2; return 1; }
  done
}

@test "paridad block-infra-destructive y validate-bash-global: destructivos ⇒ 2, inocuo ⇒ 0" {
  require_ts
  parity block-infra-destructive blockInfraDestructive 2 "terraform destroy" "kubectl delete namespace prod"
  parity block-infra-destructive blockInfraDestructive 0 "ls -la" "terraform plan"
  parity validate-bash-global validateBashGlobal 2 "chmod 777 /etc"
  parity validate-bash-global validateBashGlobal 0 "ls -la"
}
