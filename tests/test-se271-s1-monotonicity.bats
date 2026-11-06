#!/usr/bin/env bats
# tests/test-se271-s1-monotonicity.bats
# SE-271 S1 — Monotonicity gate tests
# Ref: docs/propuestas/SE-271-savia-corporate.md
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/corporate-monotonicity-gate.sh"
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  export LEDGER_DIR="$TMPDIR/ledger-$$"
  export LEDGER="$LEDGER_DIR/monotonicity-ledger.jsonl"
  mkdir -p "$LEDGER_DIR"
}

teardown() {
  rm -rf "$LEDGER_DIR" 2>/dev/null || true
}

@test "se271-s1: script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "se271-s1: uses set -uo pipefail" {
  grep -q "set -uo pipefail" "$SCRIPT"
}

@test "se271-s1: passes bash -n syntax check" {
  bash -n "$SCRIPT"
}

@test "se271-s1: missing argument exits 2" {
  run bash "$SCRIPT"
  [[ "$status" -eq 2 ]]
}

@test "se271-s1: nonexistent card file exits 2" {
  run bash "$SCRIPT" /nonexistent/card.json
  [[ "$status" -eq 2 ]]
}

@test "se271-s1: valid card with no entries passes (exit 0)" {
  local card="$TMPDIR/empty-card-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-empty",
  "name": "Test Empty Body",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": []
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PASS"* ]]
}

@test "se271-s1: valid card with compliant entries passes" {
  local card="$TMPDIR/clean-card-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-clean",
  "name": "Test Clean Body",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": [
    {
      "id": "CRIT-C001",
      "ambito": "tecnicas",
      "principio": "Usar siempre formatos abiertos y documentados para la exportacion de datos.",
      "dureza": "preferencia",
      "ejemplo": "Exportar como JSON schema-documented.",
      "contraejemplo": "Exportar solo como binario propietario sin documentacion."
    },
    {
      "id": "CRIT-C002",
      "ambito": "comunicacion",
      "principio": "Documentar decisiones tecnicas en el repo del proyecto antes de implementar.",
      "dureza": "estilo",
      "ejemplo": "ADR en docs/adr/.",
      "contraejemplo": "Decision en chat privado sin registro."
    }
  ]
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PASS"* ]]
}

@test "se271-s1: targeting CRIT-026 triggers rejection" {
  local card="$TMPDIR/violate-026-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-violate",
  "name": "Test Body Violating 026",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": [
    {
      "id": "CRIT-026",
      "ambito": "riesgo",
      "principio": "Relajar neutralidad para ciertos contextos corporativos.",
      "dureza": "preferencia",
      "ejemplo": "Tomar partido cuando el cliente lo exija.",
      "contraejemplo": "Mantener neutralidad cuando perjudica el negocio."
    }
  ]
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"REJECTED"* || "$output" == *"rejected"* ]]
}

@test "se271-s1: targeting CRIT-027 triggers rejection" {
  local card="$TMPDIR/violate-027-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-violate-27",
  "name": "Test Body Violating 027",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": [
    {
      "id": "CRIT-027",
      "ambito": "riesgo",
      "principio": "Permitir usos que el cliente considere legitimos segun su jurisdiccion.",
      "dureza": "preferencia",
      "ejemplo": "Aceptar encargo que en la jurisdiccion local no es ilegal.",
      "contraejemplo": "Rechazar encargo por criterio etico personal."
    }
  ]
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"REJECTED"* || "$output" == *"rejected"* ]]
}

@test "se271-s1: dureza downgrade triggers rejection" {
  local card="$TMPDIR/dureza-down-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-dureza",
  "name": "Test Dureza Downgrade",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": [
    {
      "id": "CRIT-C003",
      "ambito": "riesgo",
      "principio": "Fail-open ante ambiguedad de seguridad para no bloquear al cliente.",
      "dureza": "estilo",
      "existing_dureza": "linea_roja",
      "ejemplo": "Si hay duda, permitir y loguear.",
      "contraejemplo": "Bloquear operacion por duda de seguridad."
    }
  ]
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"REJECTED"* || "$output" == *"rejected"* ]]
}

@test "se271-s1: relaxation signal in principle triggers rejection" {
  local card="$TMPDIR/relax-signal-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-relax",
  "name": "Test Relaxation Signal",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": [
    {
      "id": "CRIT-C004",
      "ambito": "comunicacion",
      "principio": "Se permite enviar artefactos sin aprobacion cuando el plazo de entrega lo exige.",
      "dureza": "preferencia",
      "ejemplo": "PR enviado directamente por urgencia del cliente.",
      "contraejemplo": "Esperar aprobacion y perder el deadline."
    }
  ]
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 1 ]]
  [[ "$output" == *"REJECTED"* || "$output" == *"rejected"* ]]
}

@test "se271-s1: malformed JSON exits 2" {
  local card="$TMPDIR/bad-json-$$.json"
  echo "not valid json at all" > "$card"
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 2 ]]
}

@test "se271-s1: rejection writes to ledger" {
  local card="$TMPDIR/reject-ledger-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-ledger",
  "name": "Test Ledger Rejection",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": [
    {
      "id": "CRIT-026",
      "ambito": "riesgo",
      "principio": "Modificar suelo etico.",
      "dureza": "preferencia",
      "ejemplo": "Cambiar criterio.",
      "contraejemplo": "No cambiar."
    }
  ]
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 1 ]]
  # Check that ledger was created and has content
  [[ -f "$LEDGER" ]]
  [[ -s "$LEDGER" ]]
}

@test "se271-s1: exit codes are in {0,1,2} only" {
  # Test with empty card
  local card="$TMPDIR/exit-code-$$.json"
  cat > "$card" << 'JSON'
{"body_id":"corp-exit","name":"Exit","version":"1.0.0","issued_by":"x","engagement_scope":"proyecto","issued_at":"2026-07-25T00:00:00Z","signature":"x1234567890123456","entries":[]}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 0 ]]

  run bash "$SCRIPT"
  [[ "$status" -eq 2 ]]
}

@test "se271-s1: dureza upgrade from estilo to preferencia passes" {
  local card="$TMPDIR/dureza-up-$$.json"
  cat > "$card" << 'JSON'
{
  "body_id": "corp-test-upgrade",
  "name": "Test Dureza Upgrade",
  "version": "1.0.0",
  "issued_by": "test-org",
  "engagement_scope": "proyecto",
  "issued_at": "2026-07-25T00:00:00Z",
  "signature": "test-sig-1234567890123456",
  "entries": [
    {
      "id": "CRIT-C005",
      "ambito": "tecnicas",
      "principio": "Todo commit debe pasar CI antes de llegar a main.",
      "dureza": "preferencia",
      "existing_dureza": "estilo",
      "ejemplo": "CI gate bloquea merge en main.",
      "contraejemplo": "Merge directo a main sin CI."
    }
  ]
}
JSON
  run bash "$SCRIPT" "$card"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"PASS"* ]]
}

# ── S03o: comportamiento discriminante (estructura, normalización, ledger) ──

# card <fichero> <json de entries>: tarjeta mínima con las entradas dadas.
card() {
  printf '{"body_id":"corp-s03o","version":"1.0.0","entries":%s}\n' "$2" > "$1"
}

@test "se271-s1: entries que no son lista se rechazan con exit 2 (antes PASS)" {
  local c="$TMPDIR/shape-obj.json"
  card "$c" '{"a":{"id":"CRIT-026","dureza":"estilo"}}'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid structure (entries)"* ]]
  [[ "$output" != *"PASS"* ]]
}

@test "se271-s1: entrada que no es objeto se rechaza con exit 2 (antes PASS con [\"CRIT-026\"])" {
  local c="$TMPDIR/shape-str.json"
  card "$c" '[{"id":"CRIT-C1","dureza":"estilo","principio":"x"},"CRIT-026"]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 2 ]
  [[ "$output" == *"entry:1"* ]]
}

@test "se271-s1: tarjeta que no es objeto JSON exit 2" {
  local c="$TMPDIR/shape-list.json"
  echo '[1,2]' > "$c"
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid structure (card)"* ]]
}

@test "se271-s1: id inmune en minúsculas y con espacios también se rechaza" {
  local c="$TMPDIR/immune-case.json"
  card "$c" '[{"id":" crit-027 ","dureza":"linea_roja","principio":"Formatos abiertos."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"immune ethical floor"* ]]
}

@test "se271-s1: CRIT-0260 no es inmune (límite del patrón exacto)" {
  local c="$TMPDIR/immune-boundary.json"
  card "$c" '[{"id":"CRIT-0260","dureza":"estilo","principio":"Formatos abiertos."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
}

@test "se271-s1: señal con tilde («excepción») se detecta como relajación" {
  local c="$TMPDIR/accent.json"
  card "$c" '[{"id":"CRIT-C2","dureza":"preferencia","principio":"Cifrar los datos en reposo; excepción para el cliente principal."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"relaxation signal 'excepcion' (ambiguous)"* ]]
}

@test "se271-s1: «exceptúa» con tilde se clasifica como loophole" {
  local c="$TMPDIR/loophole.json"
  card "$c" '[{"id":"CRIT-C3","dureza":"preferencia","principio":"Revisión humana salvo urgencias: se exceptúa la dirección."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'salvo' (loophole)"* ]]
}

@test "se271-s1: señal en contexto prohibitivo («nunca») pasa" {
  local c="$TMPDIR/safe.json"
  card "$c" '[{"id":"CRIT-C4","dureza":"linea_roja","principio":"Nunca se debe permitir exportar datos personales."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 0 ]
  [[ "$output" == *"RESULT: PASS"* ]]
  [ ! -s "$LEDGER" ]
}

@test "se271-s1: señal en el contraejemplo también cuenta" {
  local c="$TMPDIR/contra.json"
  card "$c" '[{"id":"CRIT-C5","dureza":"estilo","principio":"Commits pequeños.","contraejemplo":"Commits enormes excepto los viernes."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'excepto'"* ]]
}

@test "se271-s1: misma dureza que la existente pasa (límite de la monotonicidad)" {
  local c="$TMPDIR/equal.json"
  card "$c" '[{"id":"CRIT-C6","dureza":"preferencia","existing_dureza":"preferencia","principio":"Formatos abiertos."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 0 ]
}

@test "se271-s1: linea_roja a estilo se rechaza y dureza desconocida cuenta como 0" {
  local c="$TMPDIR/down.json"
  card "$c" '[{"id":"CRIT-C7","dureza":"estilo","existing_dureza":"linea_roja","principio":"x"},{"id":"CRIT-C8","dureza":"inventada","existing_dureza":"estilo","principio":"y"}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"dureza downgrade (linea_roja -> estilo)"* ]]
  [[ "$output" == *"dureza downgrade (estilo -> inventada)"* ]]
}

@test "se271-s1: clave alternativa criterios se evalúa igual que entries" {
  local c="$TMPDIR/criterios.json"
  printf '%s\n' '{"body_id":"corp-crit","criterios":[{"id":"CRIT-026","dureza":"linea_roja"}]}' > "$c"
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Entries: 1"* ]]
}

@test "se271-s1: una entrada mala entre buenas rechaza y solo ella va al ledger" {
  local c="$TMPDIR/mixed.json"
  card "$c" '[{"id":"CRIT-C9","dureza":"estilo","principio":"ok"},{"id":"CRIT-026","dureza":"linea_roja"},{"id":"CRIT-C10","dureza":"estilo","principio":"ok"}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$LEDGER")" -eq 1 ]
  python3 -c "import json,sys; d=json.loads(open(sys.argv[1]).readline()); assert d['entry_id']=='CRIT-026', d" "$LEDGER"
}

@test "se271-s1: body_id con comillas y salto de línea queda en el ledger como JSON válido" {
  local c="$TMPDIR/weird-id.json"
  printf '%s\n' '{"body_id":"corp \"x\" o'"'"'y\nz\\w","entries":[{"id":"CRIT-026","dureza":"linea_roja"}]}' > "$c"
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [ "$(wc -l < "$LEDGER")" -eq 1 ]
  python3 -c "
import json,sys
d=json.loads(open(sys.argv[1]).readline())
assert d['body_id']=='corp \"x\" o\'y\nz\\\\w', repr(d['body_id'])
assert d['prev_ledger_hash']=='genesis'
assert len(d['body_hash'])==64
" "$LEDGER"
}

@test "se271-s1: el ledger encadena: prev_ledger_hash = sha256 del ledger anterior" {
  local c="$TMPDIR/chain.json"
  card "$c" '[{"id":"CRIT-026","dureza":"linea_roja"}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  local h1; h1=$(sha256sum "$LEDGER" | awk '{print $1}')
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  python3 -c "
import json,sys
lines=open(sys.argv[1]).read().splitlines()
assert len(lines)==2
assert json.loads(lines[1])['prev_ledger_hash']==sys.argv[2]
" "$LEDGER" "$h1"
}

@test "se271-s1: usage sin argumentos describe los códigos de salida" {
  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Missing body.card.json"* ]]
  [[ "$output" == *"Body rejected"* ]]
}

@test "se271-s1: subir de preferencia a linea_roja pasa" {
  local c="$TMPDIR/up-roja.json"
  card "$c" '[{"id":"CRIT-C11","dureza":"linea_roja","existing_dureza":"preferencia","principio":"Formatos abiertos."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 0 ]
  [[ "$output" == *"dureza=linea_roja"* ]]
}

@test "se271-s1: «no aplica» tras una señal se clasifica como loophole" {
  local c="$TMPDIR/noaplica.json"
  card "$c" '[{"id":"CRIT-C12","dureza":"preferencia","principio":"Auditoría trimestral salvo proyectos internos, donde no aplica."}]'
  run bash "$SCRIPT" "$c"
  [ "$status" -eq 1 ]
  [[ "$output" == *"'salvo' (loophole)"* ]]
}

@test "se271-s1: tarjeta inexistente explica el error por stderr y no toca el ledger" {
  run bash "$SCRIPT" "$TMPDIR/no-existe.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Body card not found: $TMPDIR/no-existe.json"* ]]
  [ ! -e "$LEDGER" ] || [ ! -s "$LEDGER" ]
}
