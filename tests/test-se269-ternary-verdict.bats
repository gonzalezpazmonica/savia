#!/usr/bin/env bats
# BATS tests for scripts/ternary-verdict.sh (SE-269 S2)
# Ref: docs/specs/SE-269-bmad-patterns.spec.md

SCRIPT="scripts/ternary-verdict.sh"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMPD="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPD"
}

# ── Structure / safety ────────────────────────────────────────────────────

@test "SE269-S2: script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "SE269-S2: script has valid bash syntax" {
  run bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: --banda is required" {
  run bash "$SCRIPT"
  [ "$status" -eq 1 ]
}

# ── Banda validation ──────────────────────────────────────────────────────

@test "SE269-S2: validates PASA band" {
  run bash "$SCRIPT" --banda PASA
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "PASA"'* ]]
}

@test "SE269-S2: validates RESERVAS band" {
  run bash "$SCRIPT" --banda RESERVAS --owner "@test" --motivo "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "RESERVAS"'* ]]
}

@test "SE269-S2: validates FALLA band" {
  run bash "$SCRIPT" --banda FALLA --motivo "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "FALLA"'* ]]
}

@test "SE269-S2: validates ENDURECIDA band (S1)" {
  run bash "$SCRIPT" --banda ENDURECIDA --motivo "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "ENDURECIDA"'* ]]
}

@test "SE269-S2: validates MAS_CLARA band (S1)" {
  run bash "$SCRIPT" --banda MAS_CLARA --motivo "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "MAS_CLARA"'* ]]
}

@test "SE269-S2: validates MUERTA band (S1)" {
  run bash "$SCRIPT" --banda MUERTA --motivo "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "MUERTA"'* ]]
}

@test "SE269-S2: validates APROBAR band (S3)" {
  run bash "$SCRIPT" --banda APROBAR
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "APROBAR"'* ]]
}

@test "SE269-S2: validates REHACER band (S3)" {
  run bash "$SCRIPT" --banda REHACER --motivo "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "REHACER"'* ]]
}

@test "SE269-S2: validates SEGUIR band (S3)" {
  run bash "$SCRIPT" --banda SEGUIR --motivo "test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "SEGUIR"'* ]]
}

@test "SE269-S2: rejects invalid band" {
  run bash "$SCRIPT" --banda INVALIDO
  [ "$status" -eq 2 ]
}

@test "SE269-S2: normalizes case" {
  run bash "$SCRIPT" --banda pasa
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto": "PASA"'* ]]
}

# ── AC-2.2: Hard gate restriction ─────────────────────────────────────────

@test "SE269-S2 AC-2.2: security gate rejects RESERVAS" {
  run env GATE_TYPE="security" bash "$SCRIPT" --banda RESERVAS --owner "@x" --motivo "test"
  [ "$status" -eq 1 ]
}

@test "SE269-S2 AC-2.2: confidencialidad gate rejects RESERVAS" {
  run env GATE_TYPE="confidencialidad" bash "$SCRIPT" --banda RESERVAS --owner "@x" --motivo "test"
  [ "$status" -eq 1 ]
}

@test "SE269-S2 AC-2.2: linea_roja gate rejects RESERVAS" {
  run env GATE_TYPE="linea_roja" bash "$SCRIPT" --banda RESERVAS --owner "@x" --motivo "test"
  [ "$status" -eq 1 ]
}

@test "SE269-S2 AC-2.2: security gate allows PASA" {
  run env GATE_TYPE="security" bash "$SCRIPT" --banda PASA
  [ "$status" -eq 0 ]
}

@test "SE269-S2 AC-2.2: security gate allows FALLA" {
  run env GATE_TYPE="security" bash "$SCRIPT" --banda FALLA --motivo "test"
  [ "$status" -eq 0 ]
}

# ── AC-2.3: RESERVAS must have owner ──────────────────────────────────────

@test "SE269-S2 AC-2.3: RESERVAS requires --owner" {
  run bash "$SCRIPT" --banda RESERVAS --motivo "test"
  [ "$status" -eq 1 ]
}

@test "SE269-S2 AC-2.3: RESERVAS with owner succeeds" {
  run bash "$SCRIPT" --banda RESERVAS --owner "@test" --motivo "test"
  [ "$status" -eq 0 ]
}

# ── Motivo validation ─────────────────────────────────────────────────────

@test "SE269-S2: non-PASA bands require --motivo" {
  run bash "$SCRIPT" --banda FALLA
  [ "$status" -eq 1 ]
}

@test "SE269-S2: PASA does not require --motivo" {
  run bash "$SCRIPT" --banda PASA
  [ "$status" -eq 0 ]
}

# ── --validate mode ───────────────────────────────────────────────────────

@test "SE269-S2: --validate mode outputs OK" {
  run bash "$SCRIPT" --banda PASA --validate
  [ "$status" -eq 0 ]
  [[ "$output" == "OK: PASA" ]]
}

@test "SE269-S2: --validate mode rejects invalid band" {
  run bash "$SCRIPT" --banda INVALIDO --validate
  [ "$status" -ne 0 ]
}

# ── Dimensiones JSON ──────────────────────────────────────────────────────

@test "SE269-S2: accepts valid --dimensiones JSON" {
  run bash "$SCRIPT" --banda PASA --dimensiones '[{"nombre":"test","banda":"PASA","hallazgos":[]}]'
  [ "$status" -eq 0 ]
}

@test "SE269-S2: rejects invalid --dimensiones JSON" {
  run bash "$SCRIPT" --banda PASA --dimensiones 'not-json'
  [ "$status" -eq 1 ]
}

# ── Output structure ──────────────────────────────────────────────────────

@test "SE269-S2: output contains all required fields" {
  run bash "$SCRIPT" --banda PASA --owner "@test"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"veredicto"'* ]]
  [[ "$output" == *'"motivo"'* ]]
  [[ "$output" == *'"owner"'* ]]
  [[ "$output" == *'"engram_op"'* ]]
  [[ "$output" == *'"origen"'* ]]
  [[ "$output" == *'"timestamp"'* ]]
  [[ "$output" == *'"dimensiones"'* ]]
}

@test "SE269-S2: output is valid JSON" {
  run bash "$SCRIPT" --banda PASA
  [ "$status" -eq 0 ]
  echo "$output" | python3 -m json.tool >/dev/null 2>&1
  [ "$?" -eq 0 ]
}

# ── Comportamiento discriminante (S03 calidad) ───────────────────────────────

@test "SE269-S2: usa modo estricto de bash (set -uo pipefail)" {
  grep -q '^set -uo pipefail' "$SCRIPT"
}

@test "SE269-S2: el JSON conserva motivo, owner, engram-op y origen tal cual" {
  run bash "$SCRIPT" --banda RESERVAS --owner "@ana" --motivo "falta evidencia" --engram-op "forja-7" --origen generado
  [ "$status" -eq 0 ]
  run jq -e '.veredicto == "RESERVAS" and .owner == "@ana" and .motivo == "falta evidencia" and .engram_op == "forja-7" and .origen == "generado"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: valores ausentes son null y origen por defecto es autor" {
  run bash "$SCRIPT" --banda PASA
  [ "$status" -eq 0 ]
  run jq -e '.owner == null and .engram_op == null and .origen == "autor" and .motivo == "" and .dimensiones == []' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: motivo con apóstrofo, comillas, backslash y dólar sobrevive intacto" {
  run bash "$SCRIPT" --banda FALLA --motivo "it's \"q\" \$HOME \\x"
  [ "$status" -eq 0 ]
  run jq -e '.motivo == "it'"'"'s \"q\" $HOME \\x"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: owner con apóstrofo no rompe la emisión ni se ejecuta como código" {
  run bash "$SCRIPT" --banda RESERVAS --motivo m --owner "o'); print('PWNED'); ('"
  [ "$status" -eq 0 ]
  run jq -e '.owner == "o'"'"'); print('"'"'PWNED'"'"'); ('"'"'"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: las dimensiones se incrustan como estructura, no como texto" {
  run bash "$SCRIPT" --banda PASA --dimensiones '[{"nombre":"seguridad","banda":"PASA","hallazgos":["a","b"]}]'
  [ "$status" -eq 0 ]
  run jq -e '(.dimensiones | length) == 1 and .dimensiones[0].nombre == "seguridad" and (.dimensiones[0].hallazgos | length) == 2' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: banda inválida sale con 2 y lista las válidas en stderr" {
  run bash "$SCRIPT" --banda INVALIDO
  [ "$status" -eq 2 ]
  [[ "$output" == *"banda inválida: INVALIDO"* ]]
  [[ "$output" == *"APROBAR"* ]]
}

@test "SE269-S2: validación fallida sale con 1, no con 2 (RESERVAS sin owner)" {
  run bash "$SCRIPT" --banda RESERVAS --motivo m
  [ "$status" -eq 1 ]
  [[ "$output" == *"--owner"* ]]
}

@test "SE269-S2: FALLA, MUERTA, REHACER, SEGUIR, MAS_CLARA y RESERVAS exigen motivo" {
  for b in FALLA MUERTA REHACER SEGUIR MAS_CLARA; do
    run bash "$SCRIPT" --banda "$b"
    [ "$status" -eq 1 ]
    [[ "$output" == *"requiere --motivo"* ]]
  done
  run bash "$SCRIPT" --banda RESERVAS --owner x
  [ "$status" -eq 1 ]
}

@test "SE269-S2: PASA, ENDURECIDA y APROBAR no exigen motivo" {
  for b in PASA ENDURECIDA APROBAR; do
    run bash "$SCRIPT" --banda "$b"
    [ "$status" -eq 0 ]
  done
}

@test "SE269-S2: un GATE_TYPE de otro tipo sí admite RESERVAS" {
  run env GATE_TYPE="calidad" bash "$SCRIPT" --banda RESERVAS --owner "@x" --motivo m
  [ "$status" -eq 0 ]
}

@test "SE269-S2: gate de frontera con RESERVAS no emite JSON de veredicto" {
  run env GATE_TYPE="security" bash "$SCRIPT" --banda RESERVAS --owner "@x" --motivo m
  [ "$status" -eq 1 ]
  [[ "$output" == *"CRIT-023"* ]]
  [[ "$output" != *'"veredicto"'* ]]
}

@test "SE269-S2: banda en minúsculas se normaliza también en --validate" {
  run bash "$SCRIPT" --banda reservas --owner x --motivo m --validate
  [ "$status" -eq 0 ]
  [ "$output" = "OK: RESERVAS" ]
}

@test "SE269-S2: --validate no emite JSON ni timestamp" {
  run bash "$SCRIPT" --banda PASA --validate
  [[ "$output" != *"timestamp"* ]]
}

@test "SE269-S2: --dimensiones vacío rechaza JSON inválido pero acepta array vacío" {
  run bash "$SCRIPT" --banda PASA --dimensiones '[]'
  [ "$status" -eq 0 ]
  run bash "$SCRIPT" --banda PASA --dimensiones '[{"a":'
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es JSON válido"* ]]
}

@test "SE269-S2: opción desconocida falla con error y uso" {
  run bash "$SCRIPT" --banda PASA --nope
  [ "$status" -eq 1 ]
  [[ "$output" == *"opción desconocida: --nope"* ]]
  [[ "$output" == *"Uso:"* ]]
}

@test "SE269-S2: timestamp es ISO-8601 UTC" {
  run bash "$SCRIPT" --banda PASA
  run jq -e '.timestamp | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: --help muestra usage con las tres familias de bandas y sale 1" {
  run bash "$SCRIPT" --help
  [ "$status" -eq 1 ]
  [[ "$output" == *"Bandas válidas (S1)"* && "$output" == *"Bandas válidas (S2)"* && "$output" == *"Bandas válidas (S3)"* ]]
}

@test "SE269-S2: dimensiones multilínea leídas de fichero se conservan con acentos" {
  printf '[\n  {"nombre": "confidencialidad", "banda": "FALLA", "hallazgos": ["fuga de teléfono"]}\n]\n' > "$TMPD/dims.json"
  run bash "$SCRIPT" --banda FALLA --motivo m --dimensiones "$(cat "$TMPD/dims.json")"
  [ "$status" -eq 0 ]
  run jq -e '.dimensiones[0].hallazgos[0] == "fuga de teléfono"' <<< "$output"
  [ "$status" -eq 0 ]
}

@test "SE269-S2: --dimensiones vacío falla con el error JSON del contrato (exit 1)" {
  run bash "$SCRIPT" --banda PASA --dimensiones ""
  [ "$status" -eq 1 ]
  [[ "$output" == *'--dimensiones no es JSON válido'* ]]
  [[ "$output" != *Traceback* ]]
}
