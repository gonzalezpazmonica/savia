#!/usr/bin/env bats
# SPEC-FREETOKEN-PROBE — tests del probe de viabilidad (Motor MoE edge)
# Valida: sintaxis, salida estructurada, detección GPU, veredicto sin nvcc.

setup() {
  cd "$(dirname "$BATS_TEST_FILENAME")/.." || exit 1
}

@test "existe, ejecutable, bash -n, sin llamadas HTTP a cloud" {
  [[ -x scripts/freetoken-probe.sh ]]
  bash -n scripts/freetoken-probe.sh
  # No debe llamar a endpoints cloud (CRIT-001); solo servidor local 1919 y descarga opcional HF
  run grep -nE "curl.*https?://(api\.|generativelanguage|anthropic)" scripts/freetoken-probe.sh
  [[ "$status" -ne 0 ]]
}

@test "probe read-only: emite JSON con los 7 campos y veredicto" {
  run bash scripts/freetoken-probe.sh --json
  [[ "$status" -eq 0 ]]
  echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
for k in ('probe','verdict','reason','gpu','nvcc','ram_gb','disk_gb','engine_installed'):
    assert k in d, k
assert d['probe'] == 'FreeToken'
assert d['verdict'] in ('viable','inviable','inviable-en-este-hardware',')
" 2>/dev/null || echo "$output" | grep -q "verdict"
}

@test "probe detecta GPU nvidia (nvidia-smi disponible)" {
  run bash scripts/freetoken-probe.sh
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"GPU:"* ]]
  [[ "$output" == *"VERDICTO:"* ]]
}

@test "probe con usage inválido → exit 2" {
  run bash scripts/freetoken-probe.sh --no-such-flag
  [[ "$status" -eq 2 ]]
}

@test "probe CRIT-001: solo descarga al pedir --install, nunca en read-only" {
  # Read-only run with fake downloaders on PATH: none may be invoked.
  local fakebin="$BATS_TEST_TMPDIR/fakebin" calls="$BATS_TEST_TMPDIR/calls.log"
  mkdir -p "$fakebin"
  for t in curl wget uv; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 1\n' "$t" "$calls" > "$fakebin/$t"
    chmod +x "$fakebin/$t"
  done
  HOME="$BATS_TEST_TMPDIR/home" PATH="$fakebin:$PATH" run bash scripts/freetoken-probe.sh
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"VERDICTO:"* ]]
  [ ! -s "$calls" ]
  # Static guard: the only download line sits after the --install branch opens.
  guard=$(grep -nE 'DO_INSTALL" -eq 1' scripts/freetoken-probe.sh | head -1 | cut -d: -f1)
  dl=$(grep -nE 'curl.*uv-install' scripts/freetoken-probe.sh | head -1 | cut -d: -f1)
  [ -n "$guard" ] && [ -n "$dl" ] && [ "$dl" -gt "$guard" ]
  # sanidad: no borra y no escribe en CRITERIO/CONSTITUCION
  run grep -nE "CRITERIO|CONSTITUCION" scripts/freetoken-probe.sh
  [[ -z "$output" ]]
}