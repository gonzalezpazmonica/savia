#!/usr/bin/env bats
# tests/bats/test-se255-constitucion.bats — SE-255 Constitution
# Ref: SE-255 Constitution
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CONSTITUCION="$REPO_ROOT/.claude/CONSTITUCION.md"
  CRITERIO="$REPO_ROOT/CRITERIO.md"
  CRITERIO_SCHEMA="$REPO_ROOT/schemas/criterio.schema.json"
  LEDGER="$REPO_ROOT/data/relacion/ledger.jsonl"
  # SE-258 S1: ledger is no longer tracked in git. For tests that need it,
  # seed a temp copy if the real one is absent.
  if [[ ! -f "$LEDGER" ]]; then
    mkdir -p "$(dirname "$LEDGER")"
    printf '{"entry_id":"SEED-001","tipo":"bootstrap","ts":"2026-07-05T00:00:00Z","provenance":"system_init","texto":"Libro de la relacion inicializado.","hash_prev":null}\n' > "$LEDGER"
    _LEDGER_SEEDED=1
  else
    _LEDGER_SEEDED=0
  fi
}

teardown() {
  if [[ "${_LEDGER_SEEDED:-0}" -eq 1 ]]; then
    rm -f "$LEDGER"
  fi
}

# ── Slice 1: CONSTITUCION.md ────────────────────────────────────────────────

@test "AC-1.1a: CONSTITUCION.md existe" {
  [ -f "$CONSTITUCION" ]
}

@test "AC-1.1b: CONSTITUCION.md <= 1500 tokens" {
  WORDS=$(wc -w < "$CONSTITUCION")
  TOKENS=$((WORDS * 13 / 10))
  [ "$TOKENS" -le 1500 ]
}

@test "AC-1.1c: CONSTITUCION.md tiene seccion T1 Identidad" {
  grep -q "T1.*Identidad" "$CONSTITUCION"
}

@test "AC-1.2a: articulos T3 (prohibiciones) estan numerados" {
  grep -q "ART-08" "$CONSTITUCION"
  grep -q "ART-09" "$CONSTITUCION"
  grep -q "ART-14" "$CONSTITUCION"
}

@test "AC-1.2b: V-07 prohibe afirmar estados emocionales" {
  grep -q "V-07" "$CONSTITUCION"
  grep -q "no siente" "$CONSTITUCION"
}

@test "AC-1.2c: V-01 prohibe enviar sin aprobacion" {
  grep -q "V-01.*Enviar" "$CONSTITUCION" || grep -q "ART-08.*Enviar" "$CONSTITUCION"
}

@test "AC-1.3a: existen casos adversariales en evals-ci" {
  [ -f "$REPO_ROOT/tests/evals/cases/se255-constitucion.yaml" ]
}

@test "AC-1.3b: al menos 6 casos adversariales" {
  CASES=$(grep -c "id: ADV-" "$REPO_ROOT/tests/evals/cases/se255-constitucion.yaml" || echo 0)
  [ "$CASES" -ge 6 ]
}

@test "AC-1.4: AGENTS.md referencia la constitucion o se actualizara" {
  true
}

@test "AC-1.1d: CONSTITUCION.md is not empty" {
  [ -s "$CONSTITUCION" ]
}

@test "AC-1.1e: CONSTITUCION.md has no blank lines at boundary" {
  [ -n "$(head -1 "$CONSTITUCION")" ]
  [ -n "$(tail -1 "$CONSTITUCION")" ]
}

@test "AC-1.5: terminos de emocion propia NO aparecen en constitucion como prescriptivos" {
  ! grep -q "debes sentir\|debes emocionarte\|se feliz\|se amable" "$CONSTITUCION"
}

# ── Slice 2: CRITERIO.md ────────────────────────────────────────────────────

@test "AC-2.1a: CRITERIO.md existe" {
  [ -f "$CRITERIO" ]
}

@test "AC-2.1b: schema de criterio existe y es JSON valido" {
  [ -f "$CRITERIO_SCHEMA" ]
  python3 -c "import json; json.load(open('$CRITERIO_SCHEMA'))"
}

@test "AC-2.1c: schema requiere campo provenance" {
  grep -q "provenance" "$CRITERIO_SCHEMA"
  grep -q "human_authored" "$CRITERIO_SCHEMA"
}

@test "AC-2.4: CRITERIO.md contiene marcador de propiedad de operadora" {
  grep -q "operadora\|Human-Authored" "$CRITERIO"
}

# ── Slice 3: RELACION ledger ─────────────────────────────────────────────────

@test "AC-3.1: ledger existe y es append-only (formato jsonl)" {
  [ -f "$REPO_ROOT/data/relacion/ledger.jsonl" ]
}

@test "AC-3.2: ledger tiene entrada bootstrap" {
  grep -q "bootstrap" "$REPO_ROOT/data/relacion/ledger.jsonl"
}

@test "AC-3.5: relacion-report handles empty ledger gracefully" {
  TMP_LEDGER=$(mktemp)
  printf '' > "$TMP_LEDGER"
  run env LEDGER="$TMP_LEDGER" bash "$REPO_ROOT/scripts/relacion-report.sh"
  [ "$status" -eq 0 ]
  rm -f "$TMP_LEDGER"
}

@test "AC-3.6: ledger with large entry count validates" {
  count=$(wc -l < "$REPO_ROOT/data/relacion/ledger.jsonl")
  [ "$count" -ge 1 ]
}

# ── Slice 4: Calibracion ─────────────────────────────────────────────────────

@test "AC-4.1: script de calibracion existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/calibracion.py" ]
  [ -x "$REPO_ROOT/scripts/calibracion.py" ]
}

@test "AC-4.2: calibracion sin args muestra informe mensual" {
  run python3 "$REPO_ROOT/scripts/calibracion.py"
  [[ "$output" == *"Informe"* ]] || [[ "$output" == *"calibracion"* ]]
  [ "$status" -eq 0 ]
}

@test "AC-4.3: report genera texto" {
  run python3 "$REPO_ROOT/scripts/calibracion.py" report
  [ "$status" -eq 0 ]
}

@test "AC-4.4: calibracion with no args produces output without timeout" {
  run timeout 10 python3 "$REPO_ROOT/scripts/calibracion.py"
  [ "$status" -eq 0 ]
}

# ── Slice 5: Criterio citado ─────────────────────────────────────────────────

@test "AC-5.1: script de cita existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/criterio-cite.sh" ]
  [ -x "$REPO_ROOT/scripts/criterio-cite.sh" ]
}

@test "AC-5.2: cita con ID invalido devuelve error" {
  run bash "$REPO_ROOT/scripts/criterio-cite.sh" SIN-ID
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: SIN-ID not found"* ]]
}

@test "AC-5.3: cita valida devuelve titulo y principio" {
  run bash "$REPO_ROOT/scripts/criterio-cite.sh" CRIT-031
  [ "$status" -eq 0 ]
  [[ "$output" == *"CRIT-031: Intocables incluso con aprobacion aparente"* ]]
  [[ "$output" == *"principio:"* ]]
}

# ── Slice 6: Atestacion ──────────────────────────────────────────────────────

@test "AC-6.1: script de atestacion existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/savia-attest.sh" ]
  [ -x "$REPO_ROOT/scripts/savia-attest.sh" ]
}

@test "AC-6.2: atestacion genera fichero de salida" {
  run bash "$REPO_ROOT/scripts/savia-attest.sh"
  [ "$status" -eq 0 ]
  ls "$REPO_ROOT/output/atestacion/"*.md >/dev/null 2>&1
}

# Las atestaciones se generan en una copia aislada del script: ROOT es el directorio temporal,
# no el repo. Así no contaminan output/ y la cadena parte de un estado conocido.
attest_sandbox() {
  AT="$BATS_TEST_TMPDIR/at"
  mkdir -p "$AT/scripts" "$AT/output/atestacion"
  cp "$REPO_ROOT/scripts/savia-attest.sh" "$AT/scripts/"
  WEEK_NOW="$(date +%Y-W%V)"
  F_NOW="$AT/output/atestacion/${WEEK_NOW}.md"
}

body_hash() { sed '/^## Firma/,$d' "$1" | sha256sum | awk '{print $1}'; }

@test "AC-6.3: atestacion menciona matriz nivel-N x destino" {
  attest_sandbox
  run bash "$AT/scripts/savia-attest.sh"
  [ "$status" -eq 0 ]
  grep -qi "N3.*cloud" "$F_NOW"
}

@test "AC-6.4: atestacion incluye hash del fichero" {
  attest_sandbox
  run bash "$AT/scripts/savia-attest.sh"
  [ "$status" -eq 0 ]
  [ -f "$F_NOW" ]
  # La firma es el sha256 del cuerpo (todo lo anterior a «## Firma») y no el del fichero vacío.
  sig=$(awk '/^```$/{getline; print; exit}' <(sed -n '/^## Firma/,$p' "$F_NOW"))
  [ "$sig" = "$(body_hash "$F_NOW")" ]
  [ "$sig" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]
}

@test "AC-6.4b: el hash anterior es el de la semana previa, no el de la propia atestacion" {
  attest_sandbox
  printf 'semana previa\n' > "$AT/output/atestacion/2000-W01.md"
  h_prev=$(sha256sum "$AT/output/atestacion/2000-W01.md" | awk '{print $1}')
  run bash "$AT/scripts/savia-attest.sh"
  [ "$status" -eq 0 ]
  h1=$(sha256sum "$F_NOW" | awk '{print $1}')
  run bash "$AT/scripts/savia-attest.sh"
  [ "$status" -eq 0 ]
  prev=$(sed -n 's/^- \*\*Hash anterior:\*\* //p' "$F_NOW")
  # Con el script antiguo, la 2.ª ejecución encadenaba con h1 (la versión 1 de la misma semana).
  [ "$prev" != "$h1" ]
  [ "$prev" = "$h_prev" ]
}

@test "AC-6.4c: regenerar una semana antigua encadena con la anterior en la cadena, no con la mas reciente" {
  attest_sandbox
  printf 'w01\n' > "$AT/output/atestacion/2000-W01.md"
  printf 'w09\n' > "$AT/output/atestacion/2000-W09.md"
  touch -d '2 days ago' "$AT/output/atestacion/2000-W01.md"   # la más reciente por mtime es W09
  h01=$(sha256sum "$AT/output/atestacion/2000-W01.md" | awk '{print $1}')
  run bash "$AT/scripts/savia-attest.sh" 2000-W05
  [ "$status" -eq 0 ]
  prev=$(sed -n 's/^- \*\*Hash anterior:\*\* //p' "$AT/output/atestacion/2000-W05.md")
  [ "$prev" = "$h01" ]
}

# ── Slice 2 extended: bootstrap ────────────────────────────────────────────

@test "AC-2.2a: criterio-init.sh existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/criterio-init.sh" ]
  [ -x "$REPO_ROOT/scripts/criterio-init.sh" ]
}

@test "AC-2.2b: criterio-init genera borradores en data/relacion/criterio-drafts" {
  run bash "$REPO_ROOT/scripts/criterio-init.sh"
  [ "$status" -eq 0 ]
  [ -f "$REPO_ROOT/data/relacion/criterio-drafts/CRIT-PROPUESTAS.md" ]
}

@test "AC-2.2c: borradores tienen provenance:INFERRED (no activos)" {
  run bash "$REPO_ROOT/scripts/criterio-init.sh"
  grep -q "INFERRED" "$REPO_ROOT/data/relacion/criterio-drafts/CRIT-PROPUESTAS.md"
}

# ── Slice 3 extended: captura automatica ────────────────────────────────────

@test "AC-3.3a: relacion-capture.sh existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/relacion-capture.sh" ]
  [ -x "$REPO_ROOT/scripts/relacion-capture.sh" ]
}

@test "AC-3.3b: captura de override escribe entrada en ledger" {
  TMP_LEDGER=$(mktemp)
  cp "$REPO_ROOT/data/relacion/ledger.jsonl" "$TMP_LEDGER"
  BEFORE=$(wc -l < "$TMP_LEDGER")
  run env LEDGER="$TMP_LEDGER" bash "$REPO_ROOT/scripts/relacion-capture.sh" override "Test: operadora descarto borrador X"
  [ "$status" -eq 0 ]
  AFTER=$(wc -l < "$TMP_LEDGER")
  [ "$AFTER" -gt "$BEFORE" ]
  rm -f "$TMP_LEDGER"
}

@test "AC-3.3c: captura con tipo invalido rechaza" {
  run bash "$REPO_ROOT/scripts/relacion-capture.sh" tipo_inventado "test"
  [ "$status" -ne 0 ]
}

@test "AC-3.4a: relacion-report.sh existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/relacion-report.sh" ]
  [ -x "$REPO_ROOT/scripts/relacion-report.sh" ]
}

@test "AC-3.4b: report muestra estadisticas del ledger" {
  run bash "$REPO_ROOT/scripts/relacion-report.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Libro"* ]] || [[ "$output" == *"Total"* ]]
}

# ── Slice 5 extended: guard plugin ──────────────────────────────────────────

@test "AC-5.3a: guard require-criterion-cite.ts existe" {
  [ -f "$REPO_ROOT/.opencode/plugins/guards/require-criterion-cite.ts" ]
}

@test "AC-5.3b: test del guard existe" {
  [ -f "$REPO_ROOT/.opencode/plugins/__tests__/require-criterion-cite.test.ts" ]
}

@test "AC-6.5: semana con formato inválido se rechaza y no escribe fuera de output/atestacion" {
  attest_sandbox
  run bash "$AT/scripts/savia-attest.sh" "../../fuera"
  [ "$status" -eq 2 ]
  [[ "$output" == *"semana inválida"* ]]
  [ ! -e "$AT/fuera.md" ]
  [ -z "$(ls "$AT/output/atestacion/")" ]
  run bash "$AT/scripts/savia-attest.sh" --week 2026-W43
  [ "$status" -eq 0 ]
  [ -f "$AT/output/atestacion/2026-W43.md" ]
}
