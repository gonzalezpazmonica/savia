#!/usr/bin/env bats
# SE-518 S1 — Pulse: contratos con esquema y validador, lanzador, `pulse status` y canal de respaldo.
# Ref: SE-518 S1 (AC-3, AC-12 parcial, AC-17; AC-18 solo el lado Pulse). AC-1 y AC-2 dependen de Soul: no se verifican aquí.
# La batería completa vive en projects/pulse/tests/test_pulse.py (stdlib); aquí se ejecuta y se
# comprueba la CLI de extremo a extremo con un estado temporal fuera del repo.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
PULSE="$REPO_ROOT/projects/pulse/bin/pulse"

setup() {
  export PULSE_DATA_DIR="$BATS_TEST_TMPDIR/datos/pulse"
}

@test "batería unittest de Pulse S1 en verde" {
  run python3 -I "$REPO_ROOT/projects/pulse/tests/test_pulse.py"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "sin latido, status dice sin señales y nunca todo bien" {
  run "$PULSE" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pulse: sin señales"* ]]
  [[ "$output" != *"da señales"* ]]
}

@test "el lanzador propaga el código y deja inicio y fin con clase" {
  run "$PULSE" run --job-id w1 -- sh -c 'exit 3'
  [ "$status" -eq 3 ]
  run grep -c '"tipo": "job_finished"' "$PULSE_DATA_DIR/eventos.jsonl"
  [ "$output" = "1" ]
  run grep '"rc": 3' "$PULSE_DATA_DIR/eventos.jsonl"
  [[ "$output" == *'"clase": "desconocida"'* ]]
}

@test "un fin genera la petición con las cinco cosas y la lista el inbox" {
  run "$PULSE" run --job-id w1 -- true
  [ "$status" -eq 0 ]
  run "$PULSE" inbox
  [[ "$output" == *"Por qué ahora"* && "$output" == *"Si no contestas"* && "$output" == *"Si aplazas"* && "$output" == *"Vale hasta"* ]]
}

@test "negativo: entrada inválida sale con 2 y no escribe nada" {
  run "$PULSE" run --job-id 'a;b' -- true
  [ "$status" -eq 2 ]
  [ ! -e "$PULSE_DATA_DIR/eventos.jsonl" ]
}

@test "negativo: con Soul presente el respaldo no emite" {
  "$PULSE" run --job-id w1 -- true
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  later=$(date -u -d '+2 minutes' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v+2M +%Y-%m-%dT%H:%M:%SZ)
  printf '{"schema_version":"1","at":"%s","valid_until":"%s"}' "$now" "$later" > "$PULSE_DATA_DIR/presencia.json"
  chmod 600 "$PULSE_DATA_DIR/presencia.json"
  run "$PULSE" deliver
  [ "$status" -eq 0 ]
  [[ "$output" == *"Soul presente: no emito nada"* ]]
  run grep -c aviso_respaldo "$PULSE_DATA_DIR/eventos.jsonl"
  [ "$output" = "0" ]
}

@test "sin Soul el respaldo avisa una vez y no repite" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"        # notificador falso: nunca avisa de verdad en el escritorio
  printf '#!/bin/sh\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/notify-send"
  chmod +x "$BATS_TEST_TMPDIR/bin/notify-send"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  "$PULSE" run --job-id w1 -- true
  run "$PULSE" deliver
  [ "$status" -eq 0 ]
  [[ "$output" == *"Avisos por respaldo: 1"* ]]
  run "$PULSE" deliver
  [ "$status" -eq 0 ]
  [[ "$output" == *"Avisos por respaldo: 0"* ]]
}

@test "negativo: con el ledger inseguro el respaldo no avisa y sale con 1" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\ntouch "%s"\n' "$BATS_TEST_TMPDIR/notificado" > "$BATS_TEST_TMPDIR/bin/notify-send"
  chmod +x "$BATS_TEST_TMPDIR/bin/notify-send"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  "$PULSE" run --job-id w1 -- true
  chmod 666 "$PULSE_DATA_DIR/eventos.jsonl"
  run "$PULSE" deliver
  [ "$status" -eq 1 ]
  [[ "$output" == *"ledger"* ]]
  [ ! -e "$BATS_TEST_TMPDIR/notificado" ]
}
