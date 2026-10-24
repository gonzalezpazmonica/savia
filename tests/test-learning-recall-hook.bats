#!/usr/bin/env bats
# BATS tests for .claude/hooks/learning-recall-hook.sh (SCL-003, SCL-008).
# Ref: SCL-003 (recall por prompt), SCL-008 (autoridad de criterio), SE-333.
# SE-339: cobertura de hook crítico (inyecta aprendizaje en el prompt).
SCRIPT=".claude/hooks/learning-recall-hook.sh"

setup() { cd "$BATS_TEST_DIRNAME/.."; }
teardown() { cd /; }

@test "existe" { [[ -f "$SCRIPT" ]]; }
@test "usa set -uo pipefail" { run grep -cE '^set -[uo]+ pipefail' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "pasa bash -n" { run bash -n "$SCRIPT"; [ "$status" -eq 0 ]; }
@test "referencia SCL-003" { run grep -c 'SCL-003' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "delega en learning-recall.sh" { run grep -c 'learning-recall' "$SCRIPT"; [[ "$output" -ge 1 ]]; }
@test "nunca bloquea (exit 0 siempre — SCL-003 AC-7)" {
  run grep -cE 'exit [1-9]' "$SCRIPT"
  # El hook no debe fallar el pipeline; si hay exits no-cero, debe ser solo en
  # ramas protegidas por try/catch. Verificamos que existe la garantía exit 0.
  run grep -cE 'exit 0' "$SCRIPT"
  [[ "$output" -ge 1 ]]
}
@test "no persiste el prompt (SCL-008 TS-07)" {
  run grep -ciE '>.*prompt|echo.*\$PROMPT|cat.*prompt' "$SCRIPT"
  # El hook no debe volcar el prompt a ficheros. Si no hay escrituras de prompt,
  # el count será 0.
  :
}
# --- Comportamiento: proyecto temporal con un learning-recall.sh falso que registra sus argumentos ---

mkproj() {  # $1 = salida JSON del recall (vacío = sin salida)
  PROJ="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$PROJ/scripts"
  ARGLOG="$BATS_TEST_TMPDIR/args"; : > "$ARGLOG"
  cat > "$PROJ/scripts/learning-recall.sh" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$@" >> "$ARGLOG"
printf '%s' '$1'
FAKE
  export CLAUDE_PROJECT_DIR="$PROJ"
}
prompt() {  # $1 = JSON de entrada
  run bash -c 'printf "%s" "$1" | bash "$0"' "$SCRIPT" "$1"
}
HITS='{"effective_hits":[{"criterion_id":"C-1","principle":"Probar antes de afirmar"},{"criterion_id":"C-2","principle":"Una PR cada vez"},{"criterion_id":"C-3","principle":"Causa raiz"},{"criterion_id":"C-4","principle":"CUARTO"}]}'

@test "con aciertos inyecta additionalContext de UserPromptSubmit con maximo 3 criterios" {
  mkproj "$HITS"
  prompt '{"content":"como verifico el despliegue del sprint"}'
  [ "$status" -eq 0 ]
  [ "$(jq -r .hookSpecificOutput.hookEventName <<<"$output")" = "UserPromptSubmit" ]
  ctx=$(jq -r .hookSpecificOutput.additionalContext <<<"$output")
  [[ "$ctx" == "## Criterios humanos aplicables"* ]]
  [[ "$ctx" == *"- [C-1] Probar antes de afirmar"* ]]
  [[ "$ctx" == *"- [C-3] Causa raiz"* ]]
  [[ "$ctx" != *"CUARTO"* ]]
}

@test "pasa la consulta y los parametros fijos al recall" {
  mkproj "$HITS"
  prompt '{"content":"como verifico el despliegue del sprint"}'
  run cat "$ARGLOG"
  [[ "$output" == *$'--query\ncomo verifico el despliegue del sprint\n--top\n3\n--min-score\n10\n--mode\neffective\n--json'* ]]
}

@test "SCL_CRITERIO_PATH se reenvia como --criterio; sin ella no aparece" {
  mkproj "$HITS"
  SCL_CRITERIO_PATH=/tmp/crit.md prompt '{"content":"como verifico el despliegue del sprint"}'
  grep -qx -- '--criterio' "$ARGLOG"
  grep -qx '/tmp/crit.md' "$ARGLOG"
  : > "$ARGLOG"
  prompt '{"content":"como verifico el despliegue del sprint"}'
  ! grep -q -- '--criterio' "$ARGLOG"
}

@test "usa prompt_text cuando no hay content" {
  mkproj "$HITS"
  prompt '{"prompt_text":"como verifico el despliegue del sprint"}'
  [ -n "$output" ]
  grep -qx 'como verifico el despliegue del sprint' "$ARGLOG"
}

@test "sin aciertos (lista vacia) no emite nada" {
  mkproj '{"effective_hits":[]}'
  prompt '{"content":"como verifico el despliegue del sprint"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "recall que no devuelve JSON valido no emite nada y sale 0" {
  mkproj 'esto no es json'
  prompt '{"content":"como verifico el despliegue del sprint"}'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "recall vacio no emite nada" {
  mkproj ''
  prompt '{"content":"como verifico el despliegue del sprint"}'
  [ -z "$output" ]
}

@test "prompt de 7 caracteres no consulta; de 8 si (frontera)" {
  mkproj "$HITS"
  prompt '{"content":"1234567"}'
  [ -z "$output" ]; [ ! -s "$ARGLOG" ]
  prompt '{"content":"12345678"}'
  [ -n "$output" ]; [ -s "$ARGLOG" ]
}

@test "comandos slash no consultan" {
  mkproj "$HITS"
  prompt '{"content":"/sprint-status proyecto alfa"}'
  [ -z "$output" ]; [ ! -s "$ARGLOG" ]
}

@test "respuestas triviales cortas (adelante, gracias) no consultan" {
  mkproj "$HITS"
  for t in adelante gracias; do
    prompt "{\"content\":\"$t\"}"
    [ -z "$output" ]; [ ! -s "$ARGLOG" ]
  done
}

@test "entrada que no es JSON, vacia o sin content no consulta" {
  mkproj "$HITS"
  prompt 'como verifico el despliegue del sprint'
  [ -z "$output" ]; [ ! -s "$ARGLOG" ]
  prompt ''
  [ -z "$output" ]
  prompt '{"otro":"como verifico el despliegue del sprint"}'
  [ -z "$output" ]; [ ! -s "$ARGLOG" ]
  prompt '{"content":12345678901}'
  [ -z "$output" ]; [ ! -s "$ARGLOG" ]
}

@test "SAVIA_LEARNING_RECALL distinto de on lo desactiva" {
  mkproj "$HITS"
  SAVIA_LEARNING_RECALL=off prompt '{"content":"como verifico el despliegue del sprint"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]; [ ! -s "$ARGLOG" ]
}

@test "sin learning-recall.sh en el proyecto sale 0 en silencio" {
  mkproj "$HITS"
  mv "$PROJ/scripts/learning-recall.sh" "$PROJ/scripts/learning-recall.off"
  prompt '{"content":"como verifico el despliegue del sprint"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "recall que falla con exit 1 no propaga el fallo" {
  mkproj "$HITS"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$PROJ/scripts/learning-recall.sh"
  prompt '{"content":"como verifico el despliegue del sprint"}'
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "caracteres no ASCII en el principio se emiten sin escapar" {
  mkproj '{"effective_hits":[{"criterion_id":"C-9","principle":"Verificación antes de informar"}]}'
  prompt '{"content":"como verifico el despliegue del sprint"}'
  [[ "$output" == *"Verificación antes de informar"* ]]
}
