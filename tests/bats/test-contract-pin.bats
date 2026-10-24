#!/usr/bin/env bats
# test-contract-pin.bats — BATS tests para SE-369 Contract Digest Pins
# Ref: docs/specs/SE-369-contract-digest-pins.spec.md — AC-0..AC-6

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  PIN="$REPO_ROOT/scripts/contract-pin.sh"
  export PIN REPO_ROOT
  # Catálogo aislado por test (CRIT-001: todo local)
  TMPDIR_SE369="$(mktemp -d)"
  export CONTRACT_DIGESTS_FILE="$TMPDIR_SE369/contract-digests.json"
  export FIXTURES="$TMPDIR_SE369"
  printf '{"schema_version": 1, "hooks": {"pre_tool": "gate.sh"}}\n' > "$FIXTURES/contract-v1.json"
}

teardown() {
  if [[ -d "${TMPDIR_SE369:-}" ]]; then
    rm -rf "$TMPDIR_SE369"
  fi
}

# ── AC-0: pin registra digest canónico y check pasa ───────────────────────────

@test "AC-0: pin registra digest sha256 y check pasa" {
  run "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PINNED"* ]]
  local expected
  expected="sha256:$(sha256sum "$FIXTURES/contract-v1.json" | cut -d' ' -f1)"
  run jq -r '.["pilot-contract"].current.digest' "$CONTRACT_DIGESTS_FILE"
  [ "$output" = "$expected" ]
  run "$PIN" check pilot-contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "AC-0: pin sin --path falla; pin con fichero inexistente falla" {
  run "$PIN" pin solo-nombre
  [ "$status" -ne 0 ]
  run "$PIN" pin fantasma --path "$FIXTURES/no-existe.json"
  [ "$status" -ne 0 ]
}

# ── AC-1: check falla si el fichero cambió sin bump ───────────────────────────

@test "AC-1: check falla tras modificar el fichero sin bump" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 1, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  run "$PIN" check pilot-contract
  [ "$status" -ne 0 ]
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"bump"* ]]
}

@test "AC-1: tras el bump, check vuelve a pasar" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  run "$PIN" check pilot-contract
  [ "$status" -ne 0 ]
  run "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json"
  [ "$status" -eq 0 ]
  run "$PIN" check pilot-contract
  [ "$status" -eq 0 ]
  run jq -r '.["pilot-contract"].current.version' "$CONTRACT_DIGESTS_FILE"
  [ "$output" = "2" ]
}

# ── AC-2: consumidor con schema antiguo rechaza nombrando el upgrade ──────────

@test "AC-2: accept con schema antiguo rechaza y nombra 'requiere upgrade a'" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" accept pilot-contract --schema 1
  [ "$status" -ne 0 ]
  [[ "$output" == *"requiere upgrade a 2"* ]]
  run "$PIN" accept pilot-contract --schema 2
  [ "$status" -eq 0 ]
}

@test "AC-2: accept con schema desconocido (mayor que current) también rechaza" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" accept pilot-contract --schema 99
  [ "$status" -ne 0 ]
  [[ "$output" == *"RECHAZADO"* ]]
}

# ── AC-3: campo aditivo aceptado solo si los conocidos son byte-idénticos ─────

@test "AC-3: campo añadido con conocidos intactos → ADITIVO (exit 0)" {
  printf '{"schema_version": 1, "hooks": {"pre_tool": "gate.sh"}}\n' > "$FIXTURES/base.json"
  printf '{"schema_version": 1, "hooks": {"pre_tool": "gate.sh"}, "nuevo_campo": true}\n' > "$FIXTURES/new.json"
  run "$PIN" additive-check --base "$FIXTURES/base.json" --new "$FIXTURES/new.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ADITIVO"* ]]
}

@test "AC-3: campo conocido modificado → BREAKING (exit 1)" {
  printf '{"schema_version": 1, "hooks": {"pre_tool": "gate.sh"}}\n' > "$FIXTURES/base.json"
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate.sh"}, "nuevo_campo": true}\n' > "$FIXTURES/new.json"
  run "$PIN" additive-check --base "$FIXTURES/base.json" --new "$FIXTURES/new.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BREAKING"* ]]
  [[ "$output" == *"schema_version"* ]]
}

@test "AC-3: campo conocido ausente → BREAKING (exit 1)" {
  printf '{"schema_version": 1, "hooks": {"pre_tool": "gate.sh"}}\n' > "$FIXTURES/base.json"
  printf '{"schema_version": 1}\n' > "$FIXTURES/new.json"
  run "$PIN" additive-check --base "$FIXTURES/base.json" --new "$FIXTURES/new.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"BREAKING"* ]]
  [[ "$output" == *"ausentes"* ]]
}

# ── AC-4: versión previa en compat pero NUNCA recupera autoridad ──────────────

@test "AC-4: tras el bump la v1 queda compat=true authoritative=false" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  run jq -r '.["pilot-contract"].previous[0] | "\(.version) \(.compat) \(.authoritative)"' "$CONTRACT_DIGESTS_FILE"
  [ "$status" -eq 0 ]
  [ "$output" = "1 true false" ]
}

@test "AC-4: compat --version 1 reporta modo compat" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" compat pilot-contract --version 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"COMPAT"* ]]
  run "$PIN" compat pilot-contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"v1"* ]]
}

@test "AC-4: re-pinear el contenido de una versión previa es rechazado" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  cp "$FIXTURES/contract-v1.json" "$FIXTURES/v1-copy.json"
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  # intento de restaurar el contenido v1 como current
  run "$PIN" pin pilot-contract --path "$FIXTURES/v1-copy.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"nunca recupera autoridad"* ]]
  # la current sigue siendo v2
  run jq -r '.["pilot-contract"].current.version' "$CONTRACT_DIGESTS_FILE"
  [ "$output" = "2" ]
}

@test "AC-4: --validate detecta catálogo manipulado con authoritative=true" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  local tmp
  tmp="$(mktemp)"
  jq '.["pilot-contract"].previous[0].authoritative = true' "$CONTRACT_DIGESTS_FILE" > "$tmp"
  mv "$tmp" "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"authoritative=false"* ]]
}

# ── AC-5: catálogo --validate consistente ─────────────────────────────────────

@test "AC-5: --validate pasa con catálogo válido tras varios pins" {
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 2, "hooks": {"pre_tool": "gate-v2.sh"}}\n' > "$FIXTURES/contract-v1.json"
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 9, "hooks": {}}\n' > "$FIXTURES/contract-v1.json"
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  "$PIN" pin c2 --path "$FIXTURES/base.json" > /dev/null 2>&1 || true
  run "$PIN" --validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"VALID"* ]]
}

@test "AC-5: --validate falla con previous sin compat" {
  printf '{"c1": {"current": {"version": 2, "digest": "sha256:%s", "path": "x.json"}, "previous": [{"version": 1, "digest": "sha256:%s", "compat": false, "authoritative": false}]}}\n' \
    "$(printf 'a%.0s' {1..64})" "$(printf 'b%.0s' {1..64})" > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"compat=true"* ]]
}

@test "AC-5: --validate falla con digest malformado" {
  printf '{"c1": {"current": {"version": 1, "digest": "md5:abc", "path": "x.json"}, "previous": []}}\n' > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"digest malformado"* ]]
}

@test "AC-5: --validate falla con current ausente" {
  printf '{"c1": {"previous": []}}\n' > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"current"* ]]
}

# ── AC-6: piloto settings-hooks pineado, sin regresión ────────────────────────

@test "AC-6: piloto settings-hooks está pineado y check pasa contra .claude/settings.json" {
  local real_catalog="$REPO_ROOT/config/contract-digests.json"
  [ -f "$real_catalog" ]
  run jq -r 'has("settings-hooks")' "$real_catalog"
  [ "$output" = "true" ]
  run env CONTRACT_DIGESTS_FILE="$real_catalog" "$PIN" check settings-hooks
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
  run env CONTRACT_DIGESTS_FILE="$real_catalog" "$PIN" --validate
  [ "$status" -eq 0 ]
}

# ── extras: robustez CLI ──────────────────────────────────────────────────────

@test "check de contrato no pineado falla; comando desconocido falla" {
  run "$PIN" check inexistente
  [ "$status" -ne 0 ]
  run "$PIN" comando-inventado
  [ "$status" -ne 0 ]
}

@test "list muestra contratos pineados" {
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"c1"* ]]
}

# ── comportamiento: idempotencia, versiones explícitas y estados de compat ────

pin_two_versions() {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"schema_version": 2}\n' > "$FIXTURES/contract-v2.json"
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v2.json" > /dev/null
}

@test "pin del mismo contenido es idempotente: exit 0, sin bump y sin previous nuevo" {
  "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" pin pilot-contract --path "$FIXTURES/contract-v1.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"sin bump"* ]]
  [ "$(jq -r '.["pilot-contract"].current.version' "$CONTRACT_DIGESTS_FILE")" = "1" ]
  [ "$(jq -r '.["pilot-contract"].previous | length' "$CONTRACT_DIGESTS_FILE")" = "0" ]
}

@test "pin con contenido nuevo incrementa la versión en uno y archiva la anterior" {
  pin_two_versions
  [ "$(jq -r '.["pilot-contract"].current.version' "$CONTRACT_DIGESTS_FILE")" = "2" ]
  [ "$(jq -r '.["pilot-contract"].previous | length' "$CONTRACT_DIGESTS_FILE")" = "1" ]
  [ "$(jq -r '.["pilot-contract"].previous[0].path' "$CONTRACT_DIGESTS_FILE")" = "$FIXTURES/contract-v1.json" ]
}

@test "pin --version explícita mayor se respeta; igual al máximo se rechaza" {
  pin_two_versions
  printf '{"schema_version": 7}\n' > "$FIXTURES/c7.json"
  run "$PIN" pin pilot-contract --path "$FIXTURES/c7.json" --version 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"debe ser > 2"* ]]
  run "$PIN" pin pilot-contract --path "$FIXTURES/c7.json" --version 1
  [ "$status" -eq 1 ]
  [ "$(jq -r '.["pilot-contract"].current.version' "$CONTRACT_DIGESTS_FILE")" = "2" ]
  run "$PIN" pin pilot-contract --path "$FIXTURES/c7.json" --version 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"v10"* ]]
  [ "$(jq -r '.["pilot-contract"].current.version' "$CONTRACT_DIGESTS_FILE")" = "10" ]
}

@test "pin de contrato nuevo con --version fija esa versión inicial" {
  run "$PIN" pin nuevo --path "$FIXTURES/contract-v1.json" --version 5
  [ "$status" -eq 0 ]
  [ "$(jq -r '.nuevo.current.version' "$CONTRACT_DIGESTS_FILE")" = "5" ]
}

@test "pin con --version no entera se rechaza sin tocar el catálogo" {
  run "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" --version abc
  [ "$status" -eq 1 ]
  [[ "$output" == *"entero"* ]]
  [ ! -f "$CONTRACT_DIGESTS_FILE" ]
}

@test "pin con argumento desconocido falla y lo nombra" {
  run "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" --bogus
  [ "$status" -eq 1 ]
  [[ "$output" == *"--bogus"* ]]
}

@test "un contrato pineado no afecta a otro: pin de c2 no toca c1" {
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  printf '{"otro": 1}\n' > "$FIXTURES/otro.json"
  "$PIN" pin c2 --path "$FIXTURES/otro.json" > /dev/null
  [ "$(jq -r '.c1.current.digest' "$CONTRACT_DIGESTS_FILE")" = "sha256:$(sha256sum "$FIXTURES/contract-v1.json" | cut -d' ' -f1)" ]
  [ "$(jq -r 'keys | length' "$CONTRACT_DIGESTS_FILE")" = "2" ]
}

@test "check con fichero ausente devuelve FAIL y exit 1; --path alternativo se usa" {
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" check c1 --path "$FIXTURES/no-existe.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"fichero ausente"* ]]
  cp "$FIXTURES/contract-v1.json" "$FIXTURES/copia.json"
  run "$PIN" check c1 --path "$FIXTURES/copia.json"
  [ "$status" -eq 0 ]
  printf 'distinto\n' > "$FIXTURES/copia.json"
  run "$PIN" check c1 --path "$FIXTURES/copia.json"
  [ "$status" -eq 1 ]
}

@test "check sin catálogo falla explicando que hay que pinear" {
  run "$PIN" check c1
  [ "$status" -eq 1 ]
  [[ "$output" == *"catálogo no encontrado"* ]]
}

@test "accept con la versión current devuelve OK y exit 0" {
  pin_two_versions
  run "$PIN" accept pilot-contract --schema 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: consumidor pilot-contract v2 == current v2"* ]]
}

@test "accept sin --schema entero falla; con contrato no pineado falla" {
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" accept c1
  [ "$status" -eq 1 ]
  run "$PIN" accept c1 --schema x
  [ "$status" -eq 1 ]
  run "$PIN" accept fantasma --schema 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"no pineado"* ]]
}

@test "accept con schema mayor aconseja actualizar el pin, no el consumidor" {
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" accept c1 --schema 3
  [ "$status" -eq 1 ]
  [[ "$output" == *"desconocido"* ]]
  [[ "$output" != *"requiere upgrade"* ]]
}

@test "compat --version de la current dice CURRENT y exit 0" {
  pin_two_versions
  run "$PIN" compat pilot-contract --version 2
  [ "$status" -eq 0 ]
  [[ "$output" == CURRENT* ]]
}

@test "compat --version inexistente: NO-COMPAT y exit 1" {
  pin_two_versions
  run "$PIN" compat pilot-contract --version 9
  [ "$status" -eq 1 ]
  [[ "$output" == NO-COMPAT* ]]
}

@test "compat --version de previous sin compat=true: NO-COMPAT y exit 1" {
  pin_two_versions
  local tmp
  tmp="$(mktemp)"
  jq '.["pilot-contract"].previous[0].compat = false' "$CONTRACT_DIGESTS_FILE" > "$tmp"
  mv "$tmp" "$CONTRACT_DIGESTS_FILE"
  run "$PIN" compat pilot-contract --version 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"compat=false"* ]]
}

@test "compat sin versión lista el número de previas y su digest" {
  pin_two_versions
  run "$PIN" compat pilot-contract
  [ "$status" -eq 0 ]
  [[ "$output" == *"previas de pilot-contract (compat, sin autoridad): 1"* ]]
  [[ "$output" == *"authoritative=false"* ]]
  [[ "$output" == *"sha256:$(sha256sum "$FIXTURES/contract-v1.json" | cut -d' ' -f1)"* ]]
}

@test "compat con --version no entera y con contrato no pineado falla" {
  pin_two_versions
  run "$PIN" compat pilot-contract --version x
  [ "$status" -eq 1 ]
  run "$PIN" compat fantasma
  [ "$status" -eq 1 ]
}

@test "additive-check: base idéntico a new es ADITIVO con 'ninguno' añadido" {
  printf '{"a": 1}\n' > "$FIXTURES/b.json"
  run "$PIN" additive-check --base "$FIXTURES/b.json" --new "$FIXTURES/b.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"añadidos: ninguno"* ]]
}

@test "additive-check: el orden de claves no cuenta (encoding canónico) y lista los campos añadidos" {
  printf '{"a": 1, "b": {"x": 1, "y": 2}}\n' > "$FIXTURES/b.json"
  printf '{"c": 3, "b": {"y": 2, "x": 1}, "a": 1}\n' > "$FIXTURES/n.json"
  run "$PIN" additive-check --base "$FIXTURES/b.json" --new "$FIXTURES/n.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"añadidos: c"* ]]
}

@test "additive-check: un campo anidado cambiado es BREAKING y nombra el campo de primer nivel" {
  printf '{"a": 1, "b": {"x": 1}}\n' > "$FIXTURES/b.json"
  printf '{"a": 1, "b": {"x": 2}}\n' > "$FIXTURES/n.json"
  run "$PIN" additive-check --base "$FIXTURES/b.json" --new "$FIXTURES/n.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"modificados"*": b"* ]]
  [[ "$output" == *"exige bump"* ]]
}

@test "additive-check: cambiado y ausente a la vez informa de ambos" {
  printf '{"a": 1, "b": 2}\n' > "$FIXTURES/b.json"
  printf '{"a": 9}\n' > "$FIXTURES/n.json"
  run "$PIN" additive-check --base "$FIXTURES/b.json" --new "$FIXTURES/n.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"modificados"*": a"* ]]
  [[ "$output" == *"ausentes: b"* ]]
}

@test "additive-check: JSON inválido y argumentos ausentes fallan con exit 1" {
  printf '{"a": 1}\n' > "$FIXTURES/b.json"
  printf 'no es json\n' > "$FIXTURES/malo.json"
  run "$PIN" additive-check --base "$FIXTURES/malo.json" --new "$FIXTURES/b.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"base no es JSON válido"* ]]
  run "$PIN" additive-check --base "$FIXTURES/b.json" --new "$FIXTURES/malo.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"new no es JSON válido"* ]]
  run "$PIN" additive-check --base "$FIXTURES/b.json"
  [ "$status" -eq 1 ]
  run "$PIN" additive-check --base "$FIXTURES/no.json" --new "$FIXTURES/b.json"
  [ "$status" -eq 1 ]
}

@test "list muestra versión, digest y ruta de cada contrato" {
  pin_two_versions
  run "$PIN" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"pilot-contract"*"v2"*"sha256:"*"contract-v2.json"* ]]
}

@test "--validate: versión previous >= current, duplicadas y previous no array se detectan" {
  local d1 d2
  d1="sha256:$(printf 'a%.0s' {1..64})"; d2="sha256:$(printf 'b%.0s' {1..64})"
  printf '{"c1": {"current": {"version": 2, "digest": "%s", "path": "x"}, "previous": [{"version": 2, "digest": "%s", "compat": true, "authoritative": false}]}}\n' "$d1" "$d2" > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"previous v2 >= current v2"* ]]
  printf '{"c1": {"current": {"version": 3, "digest": "%s", "path": "x"}, "previous": [{"version": 1, "digest": "%s", "compat": true, "authoritative": false}, {"version": 1, "digest": "%s", "compat": true, "authoritative": false}]}}\n' "$d1" "$d2" "$d2" > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicadas"* ]]
  printf '{"c1": {"current": {"version": 3, "digest": "%s", "path": "x"}, "previous": "no"}}\n' "$d1" > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"previous debe ser array"* ]]
}

@test "--validate: version no numérica y path ausente se detectan; cuenta violaciones" {
  local d1
  d1="sha256:$(printf 'a%.0s' {1..64})"
  printf '{"c1": {"current": {"version": "uno", "digest": "%s"}, "previous": []}}\n' "$d1" > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"2 violaciones"* ]]
  [[ "$output" == *"current.version debe ser número"* ]]
  [[ "$output" == *"current.path ausente"* ]]
}

@test "--validate: catálogo que no es objeto o ausente falla; válido informa nº de contratos" {
  run "$PIN" --validate
  [ "$status" -eq 1 ]
  printf '[1,2]\n' > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"no es un objeto JSON"* ]]
  "$PIN" help > /dev/null
  printf '{}\n' > "$CONTRACT_DIGESTS_FILE"
  "$PIN" pin c1 --path "$FIXTURES/contract-v1.json" > /dev/null
  "$PIN" pin c2 --path "$FIXTURES/contract-v1.json" > /dev/null
  run "$PIN" --validate
  [ "$status" -eq 0 ]
  [[ "$output" == *"(2 contratos)"* ]]
}

@test "sin argumentos muestra el uso y sale 1; help sale 0" {
  run "$PIN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"contract-pin.sh pin"* ]]
  run "$PIN" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"additive-check"* ]]
}

@test "--validate: un contrato sin current cuenta una sola violación (no encadena comprobaciones sobre el vacío)" {
  printf '{"c1": {"previous": []}, "c2": {"current": "texto", "previous": []}}\n' > "$CONTRACT_DIGESTS_FILE"
  run "$PIN" --validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"(2 violaciones)"* ]]
  [[ "$output" == *"c1: debe tener exactamente un current (objeto); encontrado: null"* ]]
  [[ "$output" == *"c2: debe tener exactamente un current (objeto); encontrado: string"* ]]
}
