#!/usr/bin/env bats
# SE-376 S03 — pr-agent-judge: el quinto juez externo de la Court solo actúa con pr-agent instalado
# Y la bandera COURT_INCLUDE_PR_AGENT=true; en cualquier otro caso se SALTA con exit 1 y un motivo
# legible (nunca devuelve un veredicto inventado). La config local pisa a la del repo. Se ejecuta
# una copia del script real en un árbol temporal para controlar docs/ y .claude/rules/.
# Ref: SPEC-124 · .claude/skills/pr-agent-judge/SKILL.md · scripts/pr-agent-run.sh
set -uo pipefail

SCRIPT="scripts/pr-agent-run.sh"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  W="${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}"
  T="$W/arbol"; BIN="$W/bin"; NOAGENT="$W/bin-sin"
  mkdir -p "$T/scripts" "$T/docs/rules/domain" "$T/.claude/rules" "$BIN" "$NOAGENT"
  cp "$ROOT/$SCRIPT" "$T/scripts/pr-agent-run.sh"
  for t in bash grep sed tr head dirname cat; do
    p="$(command -v "$t")" && { ln -sf "$p" "$BIN/$t"; ln -sf "$p" "$NOAGENT/$t"; }
  done
  # pr-agent «instalado»: basta con que exista en el PATH.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/pr-agent"; chmod +x "$BIN/pr-agent"
  # gh doble: devuelve un repo fijo.
  printf '#!/usr/bin/env bash\necho acme/widgets\n' > "$BIN/gh"; chmod +x "$BIN/gh"
  RUN="$T/scripts/pr-agent-run.sh"
  BASH_BIN="$(command -v bash)"
}

teardown() { cd /; }

flag_docs()  { printf '%s\n' "$1" > "$T/docs/rules/domain/pm-config.md"; }
flag_local() { printf '%s\n' "$1" > "$T/.claude/rules/pm-config.local.md"; }
run_w() { run env PATH="$BIN" "$BASH_BIN" "$RUN" "$@"; }
status_of() { printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'; }
field_of()  { printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

@test "con pr-agent y la bandera en true → READY, exit 0, JSON de la Court con el PR y el modo" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  run_w --pr-number 7 --repo acme/widgets
  [ "$status" -eq 0 ]
  [ "$(status_of)" = "READY" ]
  [ "$(field_of pr)" = "acme/widgets#7" ]
  [ "$(field_of mode)" = "review" ]
  [ "$(field_of judge)" = "pr-agent" ]
}

@test "--mode se refleja en la salida" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  run_w --pr-number 7 --repo acme/widgets --mode improve
  [ "$status" -eq 0 ]
  [ "$(field_of mode)" = "improve" ]
}

@test "sin la bandera en ningún fichero (missing) → SKIPPED, exit 1, current=false" {
  run_w --pr-number 7 --repo acme/widgets
  [ "$status" -eq 1 ]
  [ "$(status_of)" = "SKIPPED" ]
  [[ "$(field_of reason)" == *"feature flag not enabled (current=false)"* ]]
}

@test "bandera en false → SKIPPED, exit 1" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=false'
  run_w --pr-number 7 --repo acme/widgets
  [ "$status" -eq 1 ]
  [ "$(status_of)" = "SKIPPED" ]
}

@test "boundary: valores casi verdaderos (TRUE, truee, 1) NO activan el juez" {
  for v in TRUE truee 1 yes; do
    flag_docs "COURT_INCLUDE_PR_AGENT=$v"
    run_w --pr-number 7 --repo acme/widgets
    [ "$status" -eq 1 ]
    [ "$(status_of)" = "SKIPPED" ]
  done
}

@test "formato documentado de pm-config (espacios alrededor de =, comentario final) se interpreta como true" {
  flag_docs 'COURT_INCLUDE_PR_AGENT      = true      # opt-in: añade pr-agent como 5º juez externo'
  run_w --pr-number 7 --repo acme/widgets
  [ "$status" -eq 0 ]
  [ "$(status_of)" = "READY" ]
}

@test "la config local pisa a la del repo: local=false desactiva aunque el repo diga true" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  flag_local 'COURT_INCLUDE_PR_AGENT=false'
  run_w --pr-number 7 --repo acme/widgets
  [ "$status" -eq 1 ]
  [ "$(status_of)" = "SKIPPED" ]
}

@test "la config local pisa a la del repo: local=true activa aunque el repo diga false" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=false'
  flag_local 'COURT_INCLUDE_PR_AGENT=true'
  run_w --pr-number 7 --repo acme/widgets
  [ "$status" -eq 0 ]
  [ "$(status_of)" = "READY" ]
}

@test "pr-agent no instalado → SKIPPED exit 1 aunque la bandera esté en true (nunca finge un veredicto)" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  run env PATH="$NOAGENT" "$BASH_BIN" "$RUN" --pr-number 7 --repo acme/widgets
  [ "$status" -eq 1 ]
  [ "$(status_of)" = "SKIPPED" ]
  [[ "$(field_of reason)" == *"pr-agent not installed"* ]]
  [[ "$output" != *"READY"* ]]
}

@test "error: sin --pr-number → exit 2" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  run_w --repo acme/widgets
  [ "$status" -eq 2 ]
  [[ "$output" == *"--pr-number required"* ]]
}

@test "error: argumento desconocido → exit 2 y no ejecuta nada" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  run_w --pr-number 7 --bogus x
  [ "$status" -eq 2 ]
  [[ "$output" != *"READY"* ]]
}

@test "sin --repo se detecta con gh y se usa en el PR" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  run_w --pr-number 9
  [ "$status" -eq 0 ]
  [ "$(field_of pr)" = "acme/widgets#9" ]
}

@test "error: sin --repo y sin gh utilizable (empty) → exit 2, no inventa repositorio" {
  flag_docs 'COURT_INCLUDE_PR_AGENT=true'
  printf '#!/usr/bin/env bash\nexit 1\n' > "$BIN/gh"
  run_w --pr-number 9
  [ "$status" -eq 2 ]
  [[ "$output" == *"--repo required"* ]]
}
