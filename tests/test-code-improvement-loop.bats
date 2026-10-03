#!/usr/bin/env bats
# tests/test-code-improvement-loop.bats — calibración SE-376 de la skill code-improvement-loop
# Ref: docs/rules/domain/coherence-court.md
# Ref: docs/rules/domain/double-optin-protocol.md
# Ref: .claude/skills/code-improvement-loop/SKILL.md
#
# La skill es prosa que orquesta el bucle; lo ejecutable y local son sus dos
# puertas deterministas: el doble opt-in (SPEC-186/SE-343) y el registro de
# premisas de Coherence Court (SE-350). El bucle completo NO se ejecuta aquí
# (abre PRs). Cada test ejercita comportamiento real en un directorio temporal.

SCRIPT="scripts/coherence-court.sh"
OPTIN="scripts/savia-double-optin-check.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  REPO="$PWD"
  TMP_DIR="$(mktemp -d)"
  export COHERENCE_PREMISES_DIR="$TMP_DIR/data"
  export SAVIA_OPTIN_AUDIT_LOG="$TMP_DIR/optin-audit.log"
  export SAVIA_GRANTS_DIR="$TMP_DIR/grants"
  export SAVIA_ACTIVE_USER_FILE="$TMP_DIR/active-user.md"
  printf 'active_slug: "tester"\n' > "$SAVIA_ACTIVE_USER_FILE"
  unset CODE_IMPROVEMENT_LOOP_ENABLED OVERNIGHT_SPRINT_ENABLED SAVIA_TESTING \
        COHERENCE_SCORE_PASS COHERENCE_SCORE_CONDITIONAL || true
  echo "salida de etapa" > "$TMP_DIR/stage.md"
}

teardown() {
  cd /
  [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]] && rm -rf "$TMP_DIR"
}

# ── Seguridad del script ──────────────────────────────────────────────────

@test "ambos scripts declaran set -uo pipefail" {
  run grep -c '^set -uo pipefail' "$SCRIPT" "$OPTIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"coherence-court.sh:1"* ]]
  [[ "$output" == *"savia-double-optin-check.sh:1"* ]]
}

# ── Doble opt-in: contrato de la skill ────────────────────────────────────

@test "optin: code-improvement-loop con env y flag pasa (exit 0)" {
  run env CODE_IMPROVEMENT_LOOP_ENABLED=true bash "$OPTIN" --skill code-improvement-loop --confirm-autonomous
  [ "$status" -eq 0 ]
  grep -q $'code-improvement-loop\tenv=1\tflag=1\tverdict=ok' "$SAVIA_OPTIN_AUDIT_LOG"
}

@test "optin: sin flag se bloquea aunque el env de otra skill sea true" {
  run env OVERNIGHT_SPRINT_ENABLED=true bash "$OPTIN" --skill code-improvement-loop --confirm-autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno: CODE_IMPROVEMENT_LOOP_ENABLED=true"* ]]
}

@test "optin: valor TRUE en mayúsculas se rechaza (invalid, solo 'true')" {
  run env CODE_IMPROVEMENT_LOOP_ENABLED=TRUE bash "$OPTIN" --skill code-improvement-loop --confirm-autonomous
  [ "$status" -eq 1 ]
}

@test "optin: --skill sin valor es invocación inválida (exit 2)" {
  run bash "$OPTIN" --confirm-autonomous --skill
  [ "$status" -eq 2 ]
}

@test "optin: un scripts/operator-grant.sh plantado en el cwd NO concede el factor intent" {
  mkdir -p "$TMP_DIR/cwd/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP_DIR/cwd/scripts/operator-grant.sh"
  cd "$TMP_DIR/cwd"
  run bash "$REPO/$OPTIN" --skill code-improvement-loop --confirm-autonomous
  [ "$status" -eq 1 ]
  [[ "$output" == *"[FALTA] Variable de entorno"* ]]
}

@test "optin: grant vigente de la operadora vale aunque el cwd sea ajeno al repo" {
  run bash "$REPO/scripts/operator-grant.sh" grant --scope autonomy:code-improvement-loop --context "calibración"
  [ "$status" -eq 0 ]
  mkdir -p "$TMP_DIR/otro"
  cd "$TMP_DIR/otro"
  run bash "$REPO/$OPTIN" --skill code-improvement-loop --confirm-autonomous
  [ "$status" -eq 0 ]
}

@test "optin: el audit log por defecto no se escribe en el cwd ajeno" {
  unset SAVIA_OPTIN_AUDIT_LOG
  mkdir -p "$TMP_DIR/otro"
  cd "$TMP_DIR/otro"
  run bash "$REPO/$OPTIN" --skill code-improvement-loop
  [ "$status" -eq 1 ]
  [ ! -e "$TMP_DIR/otro/output" ]
}

# ── Coherence Court: registro de premisas que usa la skill ────────────────

@test "premisa del flujo code-improve tal como la documenta SKILL.md y check pasa" {
  run bash "$SCRIPT" premises code-improve-20261003 add decision "mejora 1: tests de auth" --stage improve-1
  [ "$status" -eq 0 ]
  pid="$output"
  run bash "$SCRIPT" premises code-improve-20261003 show "$pid"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"stage": "improve-1"'* ]]
  [[ "$output" == *'"kind": "decision"'* ]]
  run bash "$SCRIPT" check --flow code-improve-20261003 --stage-output "$TMP_DIR/stage.md"
  [ "$status" -eq 0 ]
}

@test "premises: flujo con barra se rechaza y no escribe fuera del directorio" {
  mkdir -p "$TMP_DIR/data/deep"
  export COHERENCE_PREMISES_DIR="$TMP_DIR/data/deep"
  run bash "$SCRIPT" premises ../../escape add fact "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid flow"* ]]
  run find "$TMP_DIR" -name '*.jsonl'
  [ -z "$output" ]
}

@test "premises: flujo vacío se rechaza (empty)" {
  run bash "$SCRIPT" premises "" init
  [ "$status" -ne 0 ]
}

@test "premises: --stage sin valor da error claro, no 'variable sin asignar'" {
  run bash "$SCRIPT" premises f add fact "x" --stage
  [ "$status" -ne 0 ]
  [[ "$output" == *"--stage requires a value"* ]]
}

@test "premises: show con id repetido devuelve el registro más reciente" {
  bash "$SCRIPT" premises f add fact "antigua" --id dup >/dev/null
  bash "$SCRIPT" premises f add fact "nueva" --id dup >/dev/null
  run bash "$SCRIPT" premises f show dup
  [ "$status" -eq 0 ]
  [[ "$output" == *'"content": "nueva"'* ]]
}

@test "premises: 30 add concurrentes dejan 30 líneas JSON válidas con ids únicos" {
  for i in $(seq 1 30); do
    bash "$SCRIPT" premises conc add decision "mejora $i" --stage "improve-$i" >/dev/null &
  done
  wait
  run python3 - "$TMP_DIR/data/coherence-premises-conc.jsonl" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1], encoding="utf-8") if l.strip()]
ids = {r["premise_id"] for r in rows}
print(len(rows), len(ids))
PY
  [ "$status" -eq 0 ]
  [ "$output" = "30 30" ]
}

@test "premises: contenido grande (100 KB) se conserva íntegro en show" {
  big="$(head -c 100000 /dev/zero | tr '\0' 'a')"
  pid="$(bash "$SCRIPT" premises big add fact "$big")"
  run bash -c "bash '$SCRIPT' premises big show '$pid' | python3 -c 'import json,sys; print(len(json.load(sys.stdin)[\"content\"]))'"
  [ "$status" -eq 0 ]
  [ "$output" = "100000" ]
}

@test "check: registro con solo líneas corruptas cuenta cero premisas y falla" {
  mkdir -p "$TMP_DIR/data"
  printf 'no-json\n{roto\n' > "$TMP_DIR/data/coherence-premises-bad.jsonl"
  run bash "$SCRIPT" check --flow bad --stage-output "$TMP_DIR/stage.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"has 0 premises"* ]]
}

@test "check: rutas con espacios funcionan" {
  export COHERENCE_PREMISES_DIR="$TMP_DIR/con espacio/data"
  echo x > "$TMP_DIR/con espacio.md"
  bash "$SCRIPT" premises f add fact "c" >/dev/null
  run bash "$SCRIPT" check --flow f --stage-output "$TMP_DIR/con espacio.md"
  [ "$status" -eq 0 ]
}

@test "skeleton: comillas y saltos de línea en premisas siguen dando YAML válido" {
  bash "$SCRIPT" premises q add fact 'dice "hola" y
otra línea: con dos puntos' >/dev/null
  run bash -c "bash '$SCRIPT' skeleton q '$TMP_DIR/stage.md' | python3 -c '
import sys, yaml
doc = sys.stdin.read().split(\"---\")[1]
d = yaml.safe_load(doc)
print(d[\"premises\"][0][\"content\"])'"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = 'dice "hola" y' ]
  [ "${lines[1]}" = 'otra línea: con dos puntos' ]
}

# ── score / gate: entradas inválidas y límites ────────────────────────────

@test "score: inyección aritmética en un argumento se rechaza sin ejecutar nada" {
  run bash "$SCRIPT" score "HOME[\$(touch $TMP_DIR/pwned)]" 0 0 0
  [ "$status" -ne 0 ]
  [ ! -e "$TMP_DIR/pwned" ]
}

@test "gate: inyección en --threshold se rechaza sin ejecutar nada" {
  run bash "$SCRIPT" gate 95 --threshold "HOME[\$(touch $TMP_DIR/pwned)]"
  [ "$status" -ne 0 ]
  [[ "$output" != *"CONDITIONAL"* ]]
  [ ! -e "$TMP_DIR/pwned" ]
}

@test "gate: inyección vía COHERENCE_SCORE_PASS se rechaza sin ejecutar nada" {
  run env COHERENCE_SCORE_PASS="HOME[\$(touch $TMP_DIR/pwned)]" bash "$SCRIPT" gate 95
  [ "$status" -ne 0 ]
  [ ! -e "$TMP_DIR/pwned" ]
}

@test "score: conteos negativos se rechazan (invalid, inflarían el score)" {
  run bash "$SCRIPT" score -4 0 0 0
  [ "$status" -ne 0 ]
  [[ "$output" != *"score=200"* ]]
}

@test "score: límites exactos 90 pass, 70 conditional, 69 fail" {
  run bash "$SCRIPT" score 0 1 0 0
  [ "$output" = "score=90 verdict=pass (C=0 H=1 M=0 L=0)" ]
  run bash "$SCRIPT" score 0 3 0 0
  [ "$output" = "score=70 verdict=conditional (C=0 H=3 M=0 L=0)" ]
  run bash "$SCRIPT" score 1 0 2 0
  [ "$output" = "score=69 verdict=fail (C=1 H=0 M=2 L=0)" ]
}

@test "gate: boundary 90 pasa, 89 y 70 condicional, 69 y zero fallan" {
  run bash "$SCRIPT" gate 90
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" gate 89
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" gate 70
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" gate 69
  [ "$status" -eq 1 ]
  run bash "$SCRIPT" gate 0
  [ "$status" -eq 1 ]
}

@test "gate: umbral condicional mayor que el de paso se rechaza (invalid)" {
  run bash "$SCRIPT" gate 80 --threshold 70 --conditional 90
  [ "$status" -ne 0 ]
  [[ "$output" == *"conditional"* ]]
}

@test "score: locale es_ES no altera la salida" {
  run env LC_ALL=es_ES.UTF-8 bash "$SCRIPT" score 0 0 1 2
  [ "$status" -eq 0 ]
  [ "$output" = "score=95 verdict=pass (C=0 H=0 M=1 L=2)" ]
}
