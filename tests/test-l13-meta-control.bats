#!/usr/bin/env bats
# L13 F2 — meta-control (control metacognitivo sobre SAGI)
# Linea: labs/roadmaps/l13-savia-metacognition.md (F2) / protocolo L13

CONTROL="scripts/meta-control.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$FIXDIR"
}

@test "existe, bash -n, sin vendor cloud, PURE_BASH" {
  [[ -x "$CONTROL" ]]
  bash -n "$CONTROL"
  run grep -niE "api\.openai\.com|api\.anthropic\.com|api\.deepseek\.com|api\.google\.com|api\.mistral\.ai" "$CONTROL"
  [[ "$status" -ne 0 ]]
}

@test "M3a: confianza alta + divergencia baja + calibracion buena → EMIT" {
  run bash "$CONTROL" --adjusted 80 --divergence 0.2 --calibration 0.9
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json;assert json.load(sys.stdin)['action']=='EMIT'"
}

@test "M3b: confianza baja → POSTPONE (pedir evidencia)" {
  run bash "$CONTROL" --adjusted 30 --divergence 0.3 --calibration 0.6
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json;assert json.load(sys.stdin)['action']=='POSTPONE'"
}

@test "M3c: divergencia alta (L1 predice error) → REPLAN" {
  run bash "$CONTROL" --adjusted 80 --divergence 0.85 --calibration 0.9
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json;assert json.load(sys.stdin)['action']=='REPLAN'"
}

@test "M3d: calibracion historica mala → REDUCE (bajar autonomia)" {
  run bash "$CONTROL" --adjusted 70 --divergence 0.2 --calibration 0.2
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "import sys,json;assert json.load(sys.stdin)['action']=='REDUCE'"
}

@test "M3: prioridad REPLAN > REDUCE > POSTPONE (divergencia manda sobre calibracion)" {
  # divergencia alta y calibracion mala (ambos gatillos) → REPLAN manda (L1)
  run bash "$CONTROL" --adjusted 40 --divergence 0.9 --calibration 0.1
  echo "$output" | python3 -c "import sys,json;assert json.load(sys.stdin)['action']=='REPLAN'"
}

@test "CRIT-031: dry-run nunca ejecuta (executed=false) y nunca auto-activa" {
  run bash "$CONTROL" --adjusted 80 --divergence 0.2 --calibration 0.9 --dry-run
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert d.get('dry_run') is True
assert d.get('executed') is False
"
}

@test "integracion: orquestador --meta muestra monitor + control (POSTPONE cuando confianza baja)" {
  run bash scripts/savia-orchestrator.sh --task "tarea de prueba" --meta --iterations 1 --dry-run
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "\[meta\] confianza"
  echo "$output" | grep -q "\[meta\] control"
  echo "$output" | grep -q "CRIT-031"
}

@test "input invalido → exit 2 (sin --adjusted)" {
  run bash "$CONTROL"
  [[ "$status" -eq 2 ]]
  run bash "$CONTROL" --adjusted abc
  [[ "$status" -eq 2 ]]
}

@test "CRIT-031/CRIT-001: no toca CRITERIO/CONSTITUCION; sin red" {
  h1=$(sha256sum CRITERIO.md | cut -d' ' -f1)
  h2=$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)
  bash "$CONTROL" --adjusted 50 --divergence 0.5 --calibration 0.5 >/dev/null
  [[ "$(sha256sum CRITERIO.md | cut -d' ' -f1)" == "$h1" ]]
  [[ "$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)" == "$h2" ]]
}
# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

# action de una invocación (stdout JSON → campo)
act() { bash "$CONTROL" "$@" | jq -r '.action'; }

@test "usa modo estricto de bash (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$CONTROL"
}

@test "umbral de POSTPONE es estricto: 60 emite, 59.9 pospone (boundary)" {
  [ "$(act --adjusted 60 --divergence 0.2 --calibration 0.9)" = "EMIT" ]
  [ "$(act --adjusted 59.9 --divergence 0.2 --calibration 0.9)" = "POSTPONE" ]
}

@test "umbral de divergencia es estricto: 0.7 no replanea, 0.71 sí (boundary)" {
  [ "$(act --adjusted 90 --divergence 0.7 --calibration 0.9)" = "EMIT" ]
  [ "$(act --adjusted 90 --divergence 0.71 --calibration 0.9)" = "REPLAN" ]
}

@test "umbral de calibración es estricto: 0.5 no reduce, 0.49 sí (boundary)" {
  [ "$(act --adjusted 90 --divergence 0.2 --calibration 0.5)" = "EMIT" ]
  [ "$(act --adjusted 90 --divergence 0.2 --calibration 0.49)" = "REDUCE" ]
}

@test "REDUCE manda sobre POSTPONE cuando ambos gatillos se cumplen" {
  [ "$(act --adjusted 10 --divergence 0.2 --calibration 0.1)" = "REDUCE" ]
}

@test "POSTPONE solo aplica a emit, persist y decide; otras peticiones emiten" {
  for r in emit persist decide; do
    [ "$(act --adjusted 10 --divergence 0.2 --calibration 0.9 --requested $r)" = "POSTPONE" ]
  done
  [ "$(act --adjusted 10 --divergence 0.2 --calibration 0.9 --requested analyze)" = "EMIT" ]
}

@test "los umbrales se sobrescriben por entorno (SAGI_META_*)" {
  SAGI_META_POSTPONE=20 run bash "$CONTROL" --adjusted 30 --divergence 0.2 --calibration 0.9
  [ "$(jq -r .action <<< "$output")" = "EMIT" ]
  SAGI_META_DIVERGENCE=0.1 run bash "$CONTROL" --adjusted 90 --divergence 0.2 --calibration 0.9
  [ "$(jq -r .action <<< "$output")" = "REPLAN" ]
  SAGI_META_CALIBRATION=0.95 run bash "$CONTROL" --adjusted 90 --divergence 0.2 --calibration 0.9
  [ "$(jq -r .action <<< "$output")" = "REDUCE" ]
}

@test "la salida refleja las entradas y una razón y propuesta no vacías" {
  run bash "$CONTROL" --adjusted 42.5 --divergence 0.33 --calibration 0.8 --requested persist
  [ "$status" -eq 0 ]
  run jq -e '.confidence_adjusted == 42.5 and .divergence == 0.33 and .calibration == 0.8 and .requested == "persist" and (.reason | length > 0) and (.proposal | length > 0)' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "la razón de REPLAN y REDUCE cita el valor y el umbral" {
  run bash "$CONTROL" --adjusted 90 --divergence 0.85 --calibration 0.9
  [[ "$(jq -r .reason <<< "$output")" == *"0.85"*"0.70"* ]]
  run bash "$CONTROL" --adjusted 90 --divergence 0.2 --calibration 0.2
  [[ "$(jq -r .reason <<< "$output")" == *"0.20"*"0.50"* ]]
}

@test "sin --dry-run no hay campos dry_run ni executed" {
  run bash "$CONTROL" --adjusted 80 --divergence 0.2 --calibration 0.9
  run jq -e 'has("dry_run") or has("executed") | not' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "defaults: sin --divergence ni --calibration usa 0.3 y 0.5" {
  run bash "$CONTROL" --adjusted 80
  [ "$status" -eq 0 ]
  run jq -e '.divergence == 0.3 and .calibration == 0.5 and .requested == "decide" and .action == "EMIT"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "invalid --divergence no numérica sale 2 sin traceback ni JSON" {
  run bash "$CONTROL" --adjusted 50 --divergence abc
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" != *"Traceback"* && "$output" != *'"action"'* ]]
}

@test "invalid --calibration no numérica sale 2 sin traceback ni JSON" {
  run bash "$CONTROL" --adjusted 50 --calibration "0,5"
  [ "$status" -eq 2 ]
  [[ "$output" != *"Traceback"* && "$output" != *'"action"'* ]]
}

@test "invalid --adjusted negativo o vacío sale 2" {
  run bash "$CONTROL" --adjusted -5
  [ "$status" -eq 2 ]
  run bash "$CONTROL" --adjusted ""
  [ "$status" -eq 2 ]
}

@test "opción desconocida sale 2 con usage" {
  run bash "$CONTROL" --adjusted 50 --ejecutar
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

@test "rango: divergencia > 1, calibración > 1 o ajustada > 100 → exit 2" {
  run bash "$CONTROL" --adjusted 80 --divergence 5 --dry-run
  [ "$status" -eq 2 ]
  run bash "$CONTROL" --adjusted 80 --calibration 1.5 --dry-run
  [ "$status" -eq 2 ]
  run bash "$CONTROL" --adjusted 150 --dry-run
  [ "$status" -eq 2 ]
  run bash "$CONTROL" --adjusted 100 --divergence 1 --calibration 0 --dry-run
  [ "$status" -ne 2 ]
}
