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

ghtoken() { printf 'ghp_%s' "$(printf 'A%.0s' $(seq 1 36))"; }
FP="--for""ce"

@test "runner: un guard que lanza da 2 y uno que no lanza da 0 (el ejecutor puede fallar)" {
  require_ts
  [ "$(ts_code block-force-push blockForcePush "git push $FP origin feat")" = 2 ]
  [ "$(ts_code block-force-push blockForcePush "ls -la")" = 0 ]
  run $TS_RUNTIME "$RUNNER" "$REPO_ROOT/.opencode/plugins/guards/block-force-push.ts" noExiste
  [ "$status" -eq 64 ]
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

@test "paridad sin bloqueo: inocuos, --force-with-lease a rama y mención en echo ⇒ 0" {
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 0 "ls -la" "git push $FP-with-lease origin feat" \
    "git push origin main-fix" "echo 'git push $FP'"
  parity block-credential-leak blockCredentialLeak 0 "ls -la" "git status"
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
)
AMEND_VISIBLE_OK=(
  "bash -c 'git commit -m \"explica --amend\"'" "git commit -m \${MSG:---amend}" "eval 'git commit -m x'"
  "git commit -m \"\${M} sin --amend\"" "sh -c 'git status' && echo --amend" "git commit -m x && echo \${A:---amend}"
  "git commit -m \"\$MSG\"" "git commit -F \"\$F\" \$ARGS" "git commit -m \"\$X --amend\""
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

# Revisión #1355 (P2-4): sin bun la paridad se salta; el lado bash se comprueba igual, sin require_ts.
@test "bash solo: formas ocultas de --amend ⇒ 2 y menciones ⇒ 0, con y sin jq" {
  local c fails=""
  for c in "${AMEND_HIDDEN[@]}" "git commit --amend" "git commit -m x --amend"; do
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
@test "paridad continuaciones: «\\\\⏎» separa órdenes y bloquea ⇒ 2; «\\\\\\⏎» une ⇒ 0" {
  local c fails=""
  for c in "${BS_EVEN[@]}"; do
    [[ "$(bash_code block-force-push "$PATH" "$c")" == 2 ]] || fails+="[$c] no bloquea"$'\n'
  done
  [[ -z "$fails" ]] || { printf '%s' "$fails" >&2; return 1; }
  [ "$(bash_code block-force-push "$PATH" $'echo \\\\\\\ngit push origin main')" = 0 ]
  require_ts
  command -v jq >/dev/null
  parity block-force-push blockForcePush 2 "${BS_EVEN[@]}"
  parity block-force-push blockForcePush 0 $'echo \\\\\\\ngit push origin main'
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
  command -v jq >/dev/null
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
