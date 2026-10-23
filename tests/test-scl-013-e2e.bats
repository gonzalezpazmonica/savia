#!/usr/bin/env bats
# SCL-013 — flujo end-to-end (P6): objetivo multi-paso
# Spec: docs/specs/SCL-013-flujo-end-to-end.spec.md (AC-1..AC-7)

SCRIPT="scripts/sagi-e2e.sh"

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
  FIXDIR=$(mktemp -d)
}

teardown() {
  rm -rf "$FIXDIR"
}

@test "AC-1: existe, bash -n, sin vendor names, set -uo pipefail" {
  [[ -x "$SCRIPT" ]]
  bash -n "$SCRIPT"
  grep -q "set -uo pipefail" "$SCRIPT"
  run grep -niE "openai|anthropic|gpt-|gemini|qwen|deepseek" "$SCRIPT"
  [[ "$status" -ne 0 ]]
}

@test "AC-2: goal alcanzable → completa ≤10 pasos con quality ≥80" {
  run bash "$SCRIPT" --goal "generar spec SDD valida desde un objetivo"
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "veredicto.*PASS"
  echo "$output" | python3 -c "
import sys, json
out = sys.stdin.read()
line = [l for l in out.splitlines() if l.startswith('{')][-1]
d = json.loads(line)
assert d['steps_used'] <= d['max_steps']
assert d['quality'] >= 80
assert d['veredicto'] == 'PASS'
"
}

@test "AC-3: --dry-run muestra el plan sin ejecutar" {
  run bash "$SCRIPT" --goal "x" --dry-run
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "dry-run"
  echo "$output" | grep -q "LEER → DECIDIR → VALIDAR → PERSISTIR → MEDIR"
}

@test "AC-4: --max-steps 2 con goal complejo → FAIL (límite duro)" {
  run bash "$SCRIPT" --goal "objetivo complejo" --max-steps 2
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "veredicto.*FAIL"
}

@test "AC-5: emite JSON reproducible con métricas del contrato" {
  run bash "$SCRIPT" --goal "probar contrato"
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
out = sys.stdin.read()
line = [l for l in out.splitlines() if l.startswith('{')][-1]
d = json.loads(line)
for k in ['ts','goal','steps_used','max_steps','quality','delta_pass','veredicto']:
    assert k in d, k
"
}

@test "AC-6: no modifica CRITERIO.md ni CONSTITUCION" {
  local h1 h2
  h1=$(sha256sum CRITERIO.md | cut -d' ' -f1)
  h2=$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)
  bash "$SCRIPT" --goal "hash test" >/dev/null
  [[ "$(sha256sum CRITERIO.md | cut -d' ' -f1)" == "$h1" ]]
  [[ "$(sha256sum .claude/CONSTITUCION.md | cut -d' ' -f1)" == "$h2" ]]
}

@test "AC-7 + RN-04: veredicto FAIL nunca auto-activa; emite delegación CRIT-031" {
  run bash "$SCRIPT" --goal "probar delegacion" --max-steps 1
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "CRIT-031\|INFERRED"
}

@test "input inválido → exit 2 (sin goal; --goal sin valor; --max-steps no entero)" {
  run bash "$SCRIPT"
  [[ "$status" -eq 2 ]]
  run bash "$SCRIPT" --goal
  [[ "$status" -eq 2 ]]
  run bash "$SCRIPT" --goal x --max-steps abc
  [[ "$status" -eq 2 ]]
}
# --- S03c: fronteras del límite duro y contrato JSON (SPEC-183) ---

json_line() { echo "$output" | grep '^{' | tail -1; }

@test "frontera: --max-steps 5 es el mínimo que pasa (steps=5, quality=100)" {
  run bash "$SCRIPT" --goal "g" --max-steps 5
  [[ "$status" -eq 0 ]]
  json_line | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['veredicto'] == 'PASS' and d['delta_pass'] is True, d
assert d['steps_used'] == 5 and d['quality'] == 100, d"
}

@test "frontera: --max-steps 4 ya falla y delta_pass es false" {
  run bash "$SCRIPT" --goal "g" --max-steps 4
  [[ "$status" -eq 0 ]]
  json_line | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['veredicto'] == 'FAIL' and d['delta_pass'] is False, d
assert d['max_steps'] == 4, d"
}

@test "frontera: --max-steps 0 (cero) falla sin abortar" {
  run bash "$SCRIPT" --goal "g" --max-steps 0
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "steps=5/0"
  json_line | grep -q '"veredicto":"FAIL"'
}

@test "max-steps negativo o decimal → exit 2" {
  run bash "$SCRIPT" --goal g --max-steps -3
  [[ "$status" -eq 2 ]]
  run bash "$SCRIPT" --goal g --max-steps 2.5
  [[ "$status" -eq 2 ]]
}

@test "flag desconocido → exit 2 con uso" {
  run bash "$SCRIPT" --goal g --nope
  [[ "$status" -eq 2 ]]
  echo "$output" | grep -q "usage"
}

@test "--goal vacío cuenta como ausente → exit 2" {
  run bash "$SCRIPT" --goal ""
  [[ "$status" -eq 2 ]]
}

@test "el JSON conserva el goal y la marca temporal ISO-8601" {
  run bash "$SCRIPT" --goal "objetivo con espacios y ñ"
  json_line | python3 -c "
import json, re, sys
d = json.loads(sys.stdin.read())
assert d['goal'] == 'objetivo con espacios y ñ', d
assert re.fullmatch(r'\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ', d['ts']), d"
}

@test "goal con comillas dobles sigue emitiendo JSON válido" {
  run bash "$SCRIPT" --goal 'decir "hola" y \ barra'
  [[ "$status" -eq 0 ]]
  json_line | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['goal'] == 'decir \"hola\" y \\\\ barra', d"
}

@test "goal con salto de línea y tabulador sigue emitiendo JSON válido" {
  run bash "$SCRIPT" --goal $'linea1\nlinea2\tcol'
  [[ "$status" -eq 0 ]]
  json_line | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['goal'] == 'linea1\nlinea2\tcol', d"
}

@test "goal con otros controles (\\b, ESC) sigue emitiendo JSON válido" {
  run bash "$SCRIPT" --goal $'a\bb\x1bc'
  [[ "$status" -eq 0 ]]
  json_line | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['goal'] == 'a\x08b\x1bc', d"
}

@test "dry-run con comillas dobles emite JSON válido" {
  run bash "$SCRIPT" --goal 'di "hola"' --dry-run
  [[ "$status" -eq 0 ]]
  json_line | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['goal'] == 'di \"hola\"', d"
}

@test "dry-run: no consume pasos, su JSON es válido y marca dry_run" {
  run bash "$SCRIPT" --goal "plan" --dry-run --max-steps 3
  [[ "$status" -eq 0 ]]
  echo "$output" | grep -q "max_steps: 3"
  if echo "$output" | grep -q "steps_used"; then false; fi
  json_line | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d == {'goal': 'plan', 'dry_run': True, 'veredicto': 'dry-run'}, d"
}

@test "falta el orquestador → exit 3 (dependencia ausente)" {
  local tree="$FIXDIR/tree"
  mkdir -p "$tree/scripts"
  cp "$SCRIPT" "$tree/scripts/sagi-e2e.sh"
  run bash "$tree/scripts/sagi-e2e.sh" --goal g
  [[ "$status" -eq 3 ]]
  echo "$output" | grep -q "falta savia-orchestrator.sh"
}
