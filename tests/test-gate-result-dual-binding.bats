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
  # Todos los directorios del PATH, no solo /usr/bin (revisión de corrección #1348 P2-4): en runners o macOS
  # con bash o coreutils en otra ruta, «sin jq» seguía teniendo todo lo demás. El primero del PATH gana, como en él.
  local d f
  local IFS=:
  for d in $PATH; do
    [[ -d "$d" ]] || continue
    for f in "$d"/*; do
      [[ "${f##*/}" == jq || -e "$NOJQ/${f##*/}" ]] && continue
      # Con `&&` como última orden del bucle, un último fichero no ejecutable hacía fallar setup_file.
      if [[ -x "$f" && ! -d "$f" ]]; then ln -s "$f" "$NOJQ/${f##*/}"; fi
    done
  done
  export BASH_BIN
  BASH_BIN="$(command -v bash)"
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
# (si jq viviera en un directorio del PATH y el filtro fallara, «sin jq» sería otra vez «con jq» sin que se notara).
require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    [[ "${SAVIA_REQUIRE_TS:-}" == "1" ]] && { echo "SAVIA_REQUIRE_TS=1 y no hay jq" >&2; return 1; }
    skip "sin jq: el lado «con jq» de la paridad no se puede comprobar aquí"
  fi
  if env PATH="$NOJQ" "$BASH_BIN" -c 'command -v jq' >/dev/null 2>&1; then
    echo "el PATH sin jq ($NOJQ) todavía resuelve jq" >&2
    return 1
  fi
}

# Código del hook bash con un PATH dado (con o sin jq). Un 2 sin «BLOQUEADO» en stderr no es un bloqueo
# de la regla sino una orden inevaluable (`hook_extract_command || exit 2`): sale «2-sin-bloqueo».
bash_code() { # hook path command
  local json err rc
  json=$(python3 -c 'import json,sys;print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$3")
  err=$(printf '%s' "$json" | env PATH="$2" CLAUDE_PROJECT_DIR="$BATS_TEST_TMPDIR" "$BASH_BIN" "$REPO_ROOT/.claude/hooks/$1.sh" 2>&1 >/dev/null)
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

# Revisión de seguridad de 8be7ba6, P2-1 y P2-2: git resuelve `heads/main` a refs/heads/main; `--mirror` fuerza
# (y borra refs remotas) sin decir --force; `--all` con lease actualiza main sin nombrarla.
@test "paridad block-force-push: heads/main, --mirror y --all con lease ⇒ 2 (revisión #1348 seguridad P2-1, P2-2)" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "git push $FP-with-lease origin HEAD:heads/main" "git push origin HEAD:heads/main" "git push origin heads/master" \
    "git push --mirror origin" "git push $FP-with-lease --mirror" "git push origin --mirror" \
    "git push $FP-with-lease --all" "git push $FP-with-lease origin --all"
}

@test "paridad sin bloqueo: --all sin forzar, heads/ dentro de otra rama y opción --allx ⇒ 0" {
  require_ts
  parity block-force-push blockForcePush 0 \
    "git push --all origin" "git push $FP-with-lease origin feat/heads/main" \
    "git push $FP-with-lease origin heads/main-fix" "git push $FP-with-lease origin feat --allx"
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

# Revisión de seguridad de 1b6eeaadf, P1-1: en `main` el TS sin ancla bloqueaba también estas formas. Elevación
# (`pkexec`, `runuser`), intérpretes con -c (`script -qc`, `fish`/`tcsh`/`csh -c`) y envoltorios con argumento
# posicional (`chroot /`, `flock fichero`) o sin él (`unbuffer`, `watch`) son inicio de orden en los dos bindings.
@test "paridad block-force-push: pkexec, runuser, script -c, fish/tcsh/csh -c, chroot, unbuffer, flock, watch ⇒ 2 (revisión #1348 seguridad P1-1, 2.ª ronda)" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "pkexec git push $FP origin feat" "runuser -u bot -- git push $FP origin feat" \
    "script -qc 'git push $FP origin feat' /dev/null" "script -c \"git reset --hard\" /dev/null" \
    "fish -c 'git push $SF'" "tcsh -c 'git push $FP origin feat'" "csh -c 'git commit --amend'" \
    "chroot / git push $SF" "unbuffer git push $FP origin feat" "flock /tmp/l git push $SF" \
    "watch git push $SF" "watch -n 5 git reset --hard" \
    "pkexec git push origin main" "pkexec git push $FP-with-lease origin main" "pkexec --user bot git push $SF"
}

@test "paridad sin bloqueo: los envoltorios nuevos con órdenes inocuas ⇒ 0" {
  require_ts
  parity block-force-push blockForcePush 0 \
    "pkexec git status" "runuser -u bot -- git push origin feat" "script -qc 'git status' /dev/null" \
    "fish -c 'git status'" "chroot / git push origin feat" "flock /tmp/l git push -u origin feat" \
    "watch git status" "unbuffer git push origin feat" "echo 'pkexec git push $FP'"
}

# Solo TS (revisión de seguridad #1348, 3.ª ronda, P1-1 y P2-2): el puerto anclado no puede bloquear menos que
# el TS de main, que no tenía ancla. Estas órdenes bloqueaban en main con prefijos fuera de la lista de
# envoltorios; el hook bash no las bloquea (tampoco en main), así que la paridad no detecta la regresión.
@test "TS no bloquea menos que en main: envoltorios no listados con force, push a main y reset --hard ⇒ 2" {
  require_ts
  local c t fails=""
  for c in "watch 'git push $FP origin feat'" "env -S 'git push $FP origin feat'" \
    "flock -w 5 /tmp/l git push $FP origin feat" "sg grp -c 'git push $FP origin feat'" \
    "unshare -r git push $FP origin feat" "nsenter -t 1 git push $SF origin feat" \
    "systemd-run --user git push $FP origin feat" "firejail git push $FP origin feat" \
    "parallel git push $FP ::: origin" "proxychains git push origin main" "caffeinate git push origin master" \
    "watch \"git push $FP-with-lease origin main\"" "firejail git reset --hard"; do
    t=$(ts_code block-force-push blockForcePush "$c")
    [[ "$t" == 2 ]] || fails+="[$c] ts=$t (esperado 2)"$'\n'
  done
  for c in "proxychains git push origin main-fix" "firejail git push origin feat" "watch 'git status'" \
    "caffeinate git push $FP-with-lease origin feat" "unshare -r git push origin release/main"; do
    t=$(ts_code block-force-push blockForcePush "$c")
    [[ "$t" == 0 ]] || fails+="[$c] ts=$t (esperado 0)"$'\n'
  done
  [[ -z "$fails" ]] || { printf '%s' "$fails" >&2; return 1; }
}

# Falso positivo del lado seguro (revisión de corrección #1348 P2-1, 3.ª ronda): cualquier palabra que empiece
# por `+` en un push se lee como refspec forzado, también dentro del texto de una opción. Fijado en los dos.
@test "paridad límite: una palabra +x dentro de un argumento del push bloquea en los dos (falso positivo documentado)" {
  require_ts
  parity block-force-push blockForcePush 2 "git push origin feat -o \"ci +skip\""
}

# Falso positivo del lado seguro (revisión de corrección #1348 P2-2): PUSH_MAIN acepta `main` como palabra
# suelta en cualquier punto de la misma orden push, también dentro del texto de un argumento. Se fija aquí
# para que, si un día se afina, cambie a 0 en bash y en TS a la vez.
@test "paridad límite: main como palabra dentro de un argumento del push bloquea en los dos (falso positivo documentado)" {
  require_ts
  parity block-force-push blockForcePush 2 \
    "git push origin feat --push-option \"fix main\"" "git push -u origin feat -o 'ci main'"
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
# Umbral de 3 s (revisión de corrección #1348 P2-3): con 1 s un runner de CI cargado podía dar un falso rojo;
# una regresión exponencial tarda minutos, así que 3 s no le quita poder de detección.
@test "TS sin vueltas atrás exponenciales: entradas ambiguas terminan en < 3 s (revisión #1348 P2-1)" {
  require_ts
  local c err ms
  # Se mide solo la llamada al guard (SAVIA_GUARD_TIME=1 la imprime), no el arranque en frío del runtime:
  # en un runner de CI cargado el arranque de bun/node podía pasar de 1 s sin que la regex tuviera culpa.
  for c in "git$(rep ' -c -a' 30)" "git$(rep ' -C -C' 30) !" "nice$(rep ' -n 5' 30)" "$SU$(rep ' -u env' 30)" \
    "timeout$(rep ' -k timeout' 30)" "su$(rep ' -c' 30) x" "su$(rep ' - -c' 30) x" "ssh$(rep ' -o x' 30) !" \
    "find$(rep ' -exec' 30) !" "flock$(rep ' -x' 30) !" "$(rep 'chroot / ' 30)!" "script$(rep ' -q' 30) x" \
    "pkexec$(rep ' -u pkexec' 30)" "git push -$(rep 'f' 3000)1"; do
    err=$(timeout 20 env SAVIA_GUARD_CMD="$c" SAVIA_GUARD_TIME=1 $TS_RUNTIME "$RUNNER" "$REPO_ROOT/.opencode/plugins/guards/block-force-push.ts" blockForcePush 2>&1 >/dev/null; echo "rc=$?")
    [[ "$err" == *"rc=0" ]] || { echo "rc inesperado: $err (${c:0:40}…)" >&2; return 1; }
    ms=$(sed -n 's/^guard-ms=\([0-9]*\).*/\1/p' <<<"$err")
    [[ -n "$ms" ]] || { echo "el runner no midió el guard: $err" >&2; return 1; }
    (( ms < 3000 )) || { echo "tarda $ms ms: ${c:0:40}…" >&2; return 1; }
  done
}

@test "paridad amend: --amend como argumento propio (también abreviado o tras -m) ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "git commit -m \"x\" --amend" "git commit -a --no-edit --amend" \
    "git commit -m\"x y\" --amend" "git -C /tmp/x commit --amend" "git commit --amend;ls" \
    "git commit --amen -m x" "git commit --am"
}

@test "paridad amend: --amend dentro del mensaje o tras un separador no bloquea ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 0 "git commit -m \"docs: explica --amend\"" \
    "git commit -m 'a --amend b'" "git commit -m x && echo --amend" "git commit -m x --amendment"
}

# Revisión #1355 (P1): con la regex de palabras, un argumento previo con $(…), <(…), 2>&1, \" o \' cortaba
# la cadena y --amend pasaba. El tokenizador de shell lo ve como argumento propio en bash, sin jq y TS.
@test "paridad amend: sustituciones, redirecciones y escapes antes de --amend siguen bloqueando ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "git commit -m \$(date +%F) --amend" \
    "git commit -F <(echo x) --amend" "git commit -m x 2>&1 --amend" "git commit -m \"a \\\" b\" --amend" \
    "git commit -m don\\'t --amend" "git commit -m \`date\` --amend" "echo \$(git commit --amend)" \
    "if git commit --amend; then :; fi" "/usr/bin/git commit --amend" \
    $'git commit -m "$(cat <<\'EOF\'\nno puedo\'\nEOF\n)" --amend' $'git commit -m x \\\n  --amend'
}

@test "paridad amend: heredoc en el mensaje, comentario y otra línea no bloquean ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 0 \
    $'git commit -m "$(cat <<\'EOF\'\nfeat: x\n\nmenciona --amend\nEOF\n)"' \
    "git commit -m x # --amend" $'git commit -m x\necho --amend' "git commit -m \"\$(echo --amend)\""
}

# El tokenizador bash tiene que acabar dentro del timeout del hook (5 s), que en PreToolUse no bloquea:
# por encima de 16 384 caracteres no se tokeniza y la coincidencia gruesa falla cerrado en ambos lados.
@test "paridad amend: orden enorme con --amend solo en el mensaje falla cerrado; justo bajo el tope, no ⇒ 2 / 0" {
  require_ts
  command -v jq >/dev/null
  local body
  body=$(printf 'x%.0s' $(seq 1 16400))
  parity block-force-push blockForcePush 2 "git commit -m \"$body --amend\""
  body=$(printf 'x%.0s' $(seq 1 16300))
  parity block-force-push blockForcePush 0 "git commit -m \"$body --amend\""
  parity block-force-push blockForcePush 2 "git commit -m \"$body\" --amend"
  SECONDS=0
  [ "$(bash_code block-force-push "$PATH" "git commit -m \"$body\" --amend")" = 2 ]
  (( SECONDS < 5 ))
}

# Revisión #1355 (P1, seguridad): cada nivel de $(…) se volvía a recorrer y 200 niveles en 1,6 KB tardaban
# 8-20 s, más que el timeout del hook, que en PreToolUse no bloquea: la orden pasaba sin evaluar. Con el
# presupuesto de pasos y el tope de anidamiento, bash acaba en tiempo y la coincidencia gruesa falla cerrado.
@test "paridad amend: sustituciones anidadas en profundidad acaban antes del timeout y fallan cerrado ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  local deep="" dq="" i
  for (( i = 0; i < 200; i++ )); do deep+='$(echo '; dq+='$(echo "'; done
  deep+="x"; dq+="x"
  for (( i = 0; i < 200; i++ )); do deep+=')'; dq+='")'; done
  SECONDS=0
  [ "$(bash_code block-force-push "$PATH" "git commit -m \"$deep\" --amend")" = 2 ]
  [ "$(bash_code block-force-push "$PATH" "git commit --amend -m \"$dq\"")" = 2 ]
  [ "$(bash_code block-force-push "$PATH" "git commit -m \"$deep --amend\"")" = 2 ]
  (( SECONDS < 5 ))
  parity block-force-push blockForcePush 2 "git commit -m \"$deep\" --amend" "git commit --amend -m \"$dq\""
  # Por debajo de los topes el tokenizador sigue distinguiendo argumento y mensaje.
  parity block-force-push blockForcePush 0 'git commit -m "$(echo "$(echo "$(echo --amend)")")"'
  parity block-force-push blockForcePush 2 'git commit -m "$(echo "$(echo "$(echo x)")")" --amend'
}

# Revisión #1355 (P2): la vía rápida buscaba «commit» y «--am» literales y se saltaba el tokenizador con
# escapes o comillas en mitad de la palabra; tras «|» con < o > entre comillas la tubería se tomaba por
# redirección; y las opciones de sudo/env cortaban el reconocimiento de git.
@test "paridad amend: escapes y comillas dentro de la palabra, tubería tras \">\" y sudo/env con opciones ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 'git co\mmit --amend' 'git commit --"amend"' "git commit --'am'end" \
    'git commit --a\mend' 'echo ">"|git commit --amend' 'sudo -u x git commit --amend' \
    'env -i git commit --amend' 'time -p git commit --amend' 'env -u HOME git commit --amend'
}

@test "paridad amend: \">\" entre comillas ante una tubería separa órdenes; opción de sudo con valor no es git ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 0 'git commit -m ">"| echo --amend' 'sudo -u commit ls --amend'
  parity block-force-push blockForcePush 2 'git commit -m x >| f --amend' 'git commit -m x 2>&1 --amend'
}

# Revisión #1355 (P2): el tope se medía en bytes en bash (LC_ALL=C) y en unidades UTF-16 en TS; con texto
# no ASCII entre ~8 K y 16 K bytes bash fallaba cerrado y TS tokenizaba. Ahora ambos miden bytes UTF-8.
@test "paridad amend: el tope de longitud cuenta bytes UTF-8 en bash y TS ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  local body
  body=$(printf 'ñ%.0s' $(seq 1 8200))
  parity block-force-push blockForcePush 2 "git commit -m \"$body --amend\""
}

# Revisión #1355 (3.ª, P1): la regex vieja de main bloqueaba estas formas por texto y el tokenizador las dejaba
# pasar: comillas $'…' y $"…", ${…}, llaves, sustitución sin comillas, git tras otro prefijo, opción global
# con valor, y órdenes dentro de bash -c, sh -c, eval o ssh.
AMEND_HIDDEN=(
  "git commit \$'--amend'" "git commit \$\"--amend\"" "git commit \${X:---amend}" "git commit \${X:- --amend}"
  "git commit {--amend,-q}" "git commit --am{end,}" "git commit \$'--am\\x65nd'" "git commit \$(echo --amend)"
  "git commit \"\$(echo --amend)\"" "\$'git' commit --amend" "git \$'commit' --amend" "echo \${X:-\$(git commit --amend)}"
  "bash -c 'cd /x && git commit --amend'" "sh -c \"git status; git commit --amend\"" "eval 'true; git commit --amend'"
  "ssh -p 22 host 'cd x; git commit --amend'" "ssh host git commit --amend" "timeout 5 git commit --amend"
  "xargs git commit --amend" "find . -exec sh -lc 'git commit --amend' \\;" "git --namespace x commit --amend"
  "git --config-env a=B commit --amend" "git --attr-source t commit --amend"
  # Revisión #1355 (4.ª, P1 correctness): expansión pegada a la palabra y comillas $'…'/$"…" que parten --amend.
  "git commit --amend\"\$X\"" "git commit --amend\$x" "git commit --amend\${x}" "git commit -\$'-amend'"
  "git commit --\$\"amend\"" "git commit -{-amend,}"
  # Integración con main (#1348): el GIT_AT de main ya ve git dentro de script -qc, tcsh -c y csh -c.
  "script -qc 'git commit --amend' /dev/null" "tcsh -c 'git commit --amend'" "csh -c 'cd x; git commit --amend'"
)
AMEND_VISIBLE_OK=(
  "bash -c 'git commit -m \"explica --amend\"'" "git commit -m \"\${MSG:---amend}\"" "eval 'git commit -m x'"
  "git commit -m \"\${M} sin --amend\"" "sh -c 'git status' && echo --amend" "git commit -m x && echo \${A:---amend}"
  "git commit -m \"\$MSG\"" "git commit -F \"\$F\" \$ARGS" "git commit -m \"\$X --amend\""
  # Revisión #1355 (6.ª): entre comillas dobles no hay separación en palabras; el valor de -m sigue siendo uno.
  "git commit -m \"\$(echo x --amend)\"" "git commit -F \"\`printf 'x --amend'\`\"" "git commit -m \$'x --amend'"
)
# Revisión #1355 (6.ª, P1 seguridad): una expansión sin comillas tras -m/-F se parte en palabras y su texto
# puede dar un --amend real (git commit -m $(echo x --amend) ⇒ -m x --amend). La regex de main los bloqueaba.
AMEND_SPLIT_HIDDEN=(
  "git commit -m \$(echo x --amend)" "git commit -m \`printf 'x --amend'\`" "git commit -m \${M:-x --amend}"
  "git commit -m \${MSG:---amend}" "git commit -F {x,--amend}" "git commit --message \$x--amend"
)

@test "paridad amend: \$'…', \${…}, llaves, git tras prefijo y bash -c/eval/ssh siguen bloqueando ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "${AMEND_HIDDEN[@]}"
}

@test "paridad amend: --amend como valor de -m o dentro del mensaje de un bash -c no bloquea ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 0 "${AMEND_VISIBLE_OK[@]}"
}

@test "paridad amend: expansión sin comillas tras -m/-F con --am dentro falla cerrado ⇒ 2 (revisión #1355, 6.ª)" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "${AMEND_SPLIT_HIDDEN[@]}"
}

# Revisión #1355 (P2-4): sin bun la paridad se salta; el lado bash se comprueba igual, sin require_ts.
@test "bash solo: formas ocultas de --amend ⇒ 2 y menciones ⇒ 0, con y sin jq" {
  local c fails=""
  for c in "${AMEND_HIDDEN[@]}" "${AMEND_SPLIT_HIDDEN[@]}" "git commit --amend" "git commit -m x --amend"; do
    [[ "$(bash_code block-force-push "$PATH" "$c")" == 2 && "$(bash_code block-force-push "$NOJQ" "$c")" == 2 ]] || fails+="[$c] no bloquea"$'\n'
  done
  for c in "${AMEND_VISIBLE_OK[@]}" "git commit -m \"docs: explica --amend\"" "git commit -m x # --amend"; do
    [[ "$(bash_code block-force-push "$PATH" "$c")" == 0 ]] || fails+="[$c] bloquea"$'\n'
  done
  [[ -z "$fails" ]] || { printf '%s' "$fails" >&2; return 1; }
}

# Revisión #1355 (P2-2 correctness): el salto de comentario gasta pasos como el resto de bucles. Un comentario
# dentro de dos $(…) cuenta 4 veces sin el arreglo (cierre y copia de cada nivel) y 5 con él: con 7500
# caracteres, 30 K pasos caben en el presupuesto (32 768) y 37,5 K no, así que decide la coincidencia gruesa.
@test "paridad amend: un comentario largo dentro de sustituciones gasta presupuesto ⇒ 2" {
  require_ts
  command -v jq >/dev/null
  local cm
  cm=$(printf 'c%.0s' $(seq 1 7500))
  parity block-force-push blockForcePush 2 "echo \$(echo \$(: # $cm"$'\n'")); git commit -m \"a --amend\""
  parity block-force-push blockForcePush 0 "echo \$(echo \$(: # c"$'\n'")); git commit -m \"a --amend\""
}

# Revisión #1355 (P2-2 security): un --force-with-lease en otra orden u otra línea no excusa un --force.
@test "paridad force: lease en otra orden o línea no excusa un --force ⇒ 2; lease solo ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "git push --force-with-lease o feat; git push $FP o feat" \
    $'git push --force-with-lease o feat\ngit push '"$FP"' o feat' "git push --force-with-lease $FP o feat"
  parity block-force-push blockForcePush 0 "git push --force-with-lease o feat" "git push --force-with-lease=feat o feat"
}

# Revisión #1355 (P2): grep evalúa por línea y \s de JS cruzaba saltos de línea; ahora ambos evalúan por línea
# tras unir las continuaciones «\⏎», que en bash ocultaban un push forzado partido en dos líneas.
@test "paridad multilínea: una orden por línea y continuaciones unidas igual en bash y TS" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 0 $'git push origin feat\necho '"$FP"
  parity block-force-push blockForcePush 2 $'git push \\\n'"$FP origin feat"
}

# Revisión #1355 (4.ª, P1 seguridad): «\\⏎» es una barra literal y un salto que separa órdenes; unir toda
# barra seguida de salto pegaba la orden siguiente a la anterior y el git dejaba de verse. Con tres barras
# la última sí continúa la línea (echo \git push … es un echo).
BS_EVEN=(
  $'echo \\\\\ngit push origin main' $'echo \\\\\ngit push '"$FP"' o feat' $'echo \\\\\ngit reset --hard'
  $'echo \\\\\ngit commit --amend'
)
@test "paridad continuaciones: «\\\\⏎» separa órdenes y bloquea ⇒ 2; «\\\\\\⏎» une y su línea suelta también cuenta" {
  local c fails=""
  for c in "${BS_EVEN[@]}"; do
    [[ "$(bash_code block-force-push "$PATH" "$c")" == 2 ]] || fails+="[$c] no bloquea"$'\n'
  done
  [[ -z "$fails" ]] || { printf '%s' "$fails" >&2; return 1; }
  # Con tres barras la unión da un echo, pero las líneas tal cual también se evalúan (6.ª revisión): 2.
  [ "$(bash_code block-force-push "$PATH" $'echo \\\\\\\ngit push origin main')" = 2 ]
  # Caso negativo: ni la unión ni ninguna línea suelta es una orden git ⇒ 0.
  [ "$(bash_code block-force-push "$PATH" $'echo \\\\\\\nfoo git push o HEAD:main')" = 0 ]
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "${BS_EVEN[@]}"
  parity block-force-push blockForcePush 0 $'echo \\\\\\\nfoo git push o HEAD:main'
}

# Revisión #1355 (6.ª): «echo \\\⏎git push origin main» daba 2 en TS (suelo sin anclar) y 0 en bash. Gana
# fallar cerrado: además de las uniones, se evalúan las líneas tal cual. La unión no siempre es lo que hace el
# shell: un comentario que acaba en «\» no continúa, y la línea siguiente se ejecuta (pasaba en bash y en TS).
BS_RAW=(
  $'echo \\\\\\\ngit push origin main' $'echo \\\\\\\ngit push o HEAD:main'
  $'# nota \\\ngit push origin HEAD:main' $'# nota \\\ngit push '"$FP"' o feat' $'# nota \\\ngit reset --hard'
  $'# nota \\\ngit commit --amend'
)
@test "paridad continuaciones: las líneas sin unir también se evalúan (comentario con «\\» final) ⇒ 2" {
  local c fails=""
  for c in "${BS_RAW[@]}"; do
    [[ "$(bash_code block-force-push "$PATH" "$c")" == 2 ]] || fails+="[$c] no bloquea"$'\n'
  done
  [[ -z "$fails" ]] || { printf '%s' "$fails" >&2; return 1; }
  # Caso negativo: la continuación normal de una orden permitida sigue pasando.
  [ "$(bash_code block-force-push "$PATH" $'git push origin \\\nfeat')" = 0 ]
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "${BS_RAW[@]}"
  parity block-force-push blockForcePush 0 $'git push origin \\\nfeat' $'# nota \\\necho git push o HEAD:main'
}

# Revisión #1355 (4.ª, P1 seguridad): cuando no se puede tokenizar (tope de bytes, de anidamiento o comilla
# abierta), la coincidencia gruesa se evaluaba sobre la orden cruda y --"amend" o co\mmit la esquivaban.
# Ahora, si la vía rápida (sin \ ' " $) vio commit … --am, se bloquea sin regex.
@test "paridad amend: sin tokenizar, --\"amend\" y co\\mmit fallan cerrado ⇒ 2" {
  local big deep="" i c fails="" cases=()
  big=$(printf 'x%.0s' $(seq 1 17000))
  for (( i = 0; i < 33; i++ )); do deep+='$(echo '; done
  deep+="x"; for (( i = 0; i < 33; i++ )); do deep+=')'; done
  cases=("git commit --\"amend\" # $big" "git co\\mmit --'am'end # $big" "git commit --\"amend\" -m \"$deep\""
    "git commit --\"amend\" -m 'abierta")
  for c in "${cases[@]}"; do
    [[ "$(bash_code block-force-push "$PATH" "$c")" == 2 ]] || fails+="[${c:0:40}] no bloquea"$'\n'
  done
  [[ -z "$fails" ]] || { printf '%s' "$fails" >&2; return 1; }
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "${cases[@]}"
}

@test "paridad block-infra-destructive y validate-bash-global: destructivos ⇒ 2, inocuo ⇒ 0" {
  require_ts
  parity block-infra-destructive blockInfraDestructive 2 "terraform destroy" "kubectl delete namespace prod"
  parity block-infra-destructive blockInfraDestructive 0 "ls -la" "terraform plan"
  parity validate-bash-global validateBashGlobal 2 "chmod 777 /etc"
  parity validate-bash-global validateBashGlobal 0 "ls -la"
}

# Revisión #1355 (5.ª): «\⏎» desaparece sin dejar espacio, y una coma de llaves no esconde --amend.
@test "paridad amend: continuación partida dentro de la palabra y llaves con coma ⇒ 2; coma entre comillas ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 $'git comm\\\nit --amend' $'git pu\\\nsh --force origin x' \
    $'git commit --am\\\nend' "git commit -{-,}amend" "git commit -{-,-}amend"
  parity block-force-push blockForcePush 0 'git commit -m "a, b"' $'git commit -m x \\\n -a' \
    $'git push --force-with-lease origin feat'
}
