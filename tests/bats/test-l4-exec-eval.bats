#!/usr/bin/env bats
# Ejecutor unico de evals L4 de comportamiento (tests/bats/l4_exec_eval.py).
# Cubre el formato comun: script en el fixture, cwd del case, aislamiento del
# entorno del operador, listas de regex, stdout_empty, json y la forma 3-5 casos.
# Ref: tests/bats/l4-exec-lib.bash

load l4-exec-lib

setup() {
  TMP=$(mktemp -d)
  S="$TMP/probe.sh"
  printf '%s\n' '#!/usr/bin/env bash' \
    'case "$1" in' \
    '  pwd) pwd ;;' \
    '  env) echo "pd=${CLAUDE_PROJECT_DIR:-unset} x=${X:-unset}" ;;' \
    '  json) printf "{\"a\":{\"b\":\"ask\"},\"n\":3}\n" ;;' \
    '  quiet) : ;;' \
    '  lines) printf "uno\ndos\n" ;;' \
    '  err) echo "malo" >&2; exit 3 ;;' \
    'esac' > "$S"
}

teardown() {
  rm -rf "$TMP"
}

_fx() { # <json de cases> -> fichero fixture
  printf '{"scenario":"t","cases":%s}\n' "$1" > "$TMP/fx.json"
}

@test "exec: stdout_match admite lista y exige todas las regex" {
  _fx '[{"id":"l","aggregate":{"script":"'"$S"'","args":["lines"],"expect":{"exit":0,"stdout_match":["^uno$","^dos$"]}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 0 ]
  _fx '[{"id":"l2","aggregate":{"script":"'"$S"'","args":["lines"],"expect":{"exit":0,"stdout_match":["^uno$","^tres$"]}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"l2"* ]]
}

@test "exec: stdout_not_match en lista falla si casa cualquiera" {
  _fx '[{"id":"nm","aggregate":{"script":"'"$S"'","args":["lines"],"expect":{"exit":0,"stdout_not_match":["tres","dos"]}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nm"* ]]
}

@test "exec: stdout_empty distingue salida vacia de no vacia" {
  _fx '[{"id":"q","aggregate":{"script":"'"$S"'","args":["quiet"],"expect":{"exit":0,"stdout_empty":true}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 0 ]
  _fx '[{"id":"q2","aggregate":{"script":"'"$S"'","args":["lines"],"expect":{"exit":0,"stdout_empty":true}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"q2"* ]]
}

@test "exec: json compara rutas jq del stdout; stdout no JSON es discrepancia, no invalido" {
  _fx '[{"id":"j","aggregate":{"script":"'"$S"'","args":["json"],"expect":{"exit":0,"json":{".a.b":"ask",".n":3}}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 0 ]
  _fx '[{"id":"j2","aggregate":{"script":"'"$S"'","args":["json"],"expect":{"exit":0,"json":{".a.b":"deny"}}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 1 ]
  _fx '[{"id":"j3","aggregate":{"script":"'"$S"'","args":["lines"],"expect":{"exit":0,"json":{".a":1}}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"j3"* ]]
}

@test "exec: cwd {dir} ejecuta en el directorio del case; sin cwd, en el repo" {
  _fx '[{"id":"c","aggregate":{"script":"'"$S"'","args":["pwd"],"cwd":"{dir}","expect":{"exit":0,"stdout_match":"/case-[^/]+$"}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 0 ]
  _fx '[{"id":"r","aggregate":{"script":"'"$S"'","args":["pwd"],"expect":{"exit":0,"stdout_match":"^'"$PWD"'$"}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 0 ]
}

@test "exec: script relativo al repo sigue resolviendo con cwd {dir}" {
  _fx '[{"id":"rel","aggregate":{"script":"tests/bats/l4-exec-lib.bash","cwd":"{dir}","expect":{"exit":0,"stdout_empty":true}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 0 ]
}

@test "exec: el entorno del operador que cambia decisiones se aisla; env del case gana" {
  _fx '[{"id":"e","aggregate":{"script":"'"$S"'","args":["env"],"expect":{"exit":0,"stdout_match":"^pd=unset x=unset$"}}}]'
  run env CLAUDE_PROJECT_DIR=/otro bash -c "source tests/bats/l4-exec-lib.bash; l4_exec_cases '$TMP/fx.json'"
  [ "$status" -eq 0 ]
  _fx '[{"id":"e2","aggregate":{"script":"'"$S"'","args":["env"],"env":{"CLAUDE_PROJECT_DIR":"{dir}"},"expect":{"exit":0,"stdout_match":"^pd=/.*case-"}}}]'
  run env CLAUDE_PROJECT_DIR=/otro bash -c "source tests/bats/l4-exec-lib.bash; l4_exec_cases '$TMP/fx.json'"
  [ "$status" -eq 0 ]
}

@test "exec: claves del formato antiguo (run, {{TMP}}) son invalidas, no se ignoran" {
  _fx '[{"id":"old","aggregate":{"script":"'"$S"'","run":["lines"],"expect":{"exit":0,"stdout_match":"uno"}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 2 ]
  _fx '[{"id":"old2","aggregate":{"script":"'"$S"'","args":["{{TMP}}"],"expect":{"exit":0,"stdout_empty":true}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 2 ]
}

@test "exec: exit 0 sin otra expectativa sigue siendo invalido" {
  _fx '[{"id":"z","aggregate":{"script":"'"$S"'","args":["quiet"],"expect":{"exit":0}}}]'
  run l4_exec_cases "$TMP/fx.json"
  [ "$status" -eq 2 ]
}

@test "exec: l4_exec_shape exige 1+ por fixture, 3-5 en total y uno negativo" {
  d="$TMP/ev"; mkdir -p "$d"
  c='{"id":"x","aggregate":{"script":"s","expect":{"exit":1}}}'
  n='{"id":"y","negative":true,"aggregate":{"script":"s","expect":{"exit":1}}}'
  for s in golden edge adversarial; do printf '{"cases":[%s]}' "$c" > "$d/$s.json"; done
  printf '{"cases":[%s]}' "$n" > "$d/bypass.json"
  run l4_exec_shape "$d"
  [ "$status" -eq 0 ]
  printf '{"cases":[%s]}' "$c" > "$d/bypass.json"
  run l4_exec_shape "$d"
  [ "$status" -eq 1 ]
  printf '{"cases":[]}' > "$d/edge.json"
  printf '{"cases":[%s]}' "$n" > "$d/bypass.json"
  run l4_exec_shape "$d"
  [ "$status" -eq 1 ]
}

@test "exec: l4_hook_copy copia hook y lib/ sin tocar el original" {
  l4_hook_copy .claude/hooks/block-force-push.sh "$TMP/hooks"
  [ -f "$TMP/hooks/block-force-push.sh" ]
  [ -d "$TMP/hooks/lib" ]
  [ ! -L "$TMP/hooks/lib" ]
}

@test "exec: solo queda un ejecutor de evals L4 de scripts" {
  [ ! -e tests/bats/l4-script-cases-lib.bash ]
  ! grep -l --exclude=test-l4-exec-eval.bats "l4_script_cases\|l4-script-cases-lib" tests/bats/*.bats
}
