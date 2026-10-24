#!/usr/bin/env bats
# BATS tests for scripts/savia-catalog.py (SE-342 S1 / Labs L17)
# Ref: SE-342 S1, hypothesis l17-data-catalog.md, CRIT-001

SCRIPT="scripts/savia-catalog.py"

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TMP_DB="$(mktemp -t catalog.XXXXXX.db)"
  rm -f "$TMP_DB" "$TMP_DB-wal" "$TMP_DB-shm"
  export SAVIA_CATALOG_DB="$TMP_DB"
  export KG_DB="$TMP_DB"
}

teardown() {
  [[ -n "$TMP_DB" ]] && rm -f "$TMP_DB" "$TMP_DB-wal" "$TMP_DB-shm"
  cd /
}

@test "script exists and is executable" {
  [[ -x "$SCRIPT" ]]
}

@test "passes py_compile" {
  run python3 -m py_compile "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "--version prints semver" {
  run python3 "$SCRIPT" --version
  [ "$status" -eq 0 ]
  [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

# ── registro ────────────────────────────────────────────────────────────

@test "register dataset requires level; list shows it" {
  run python3 "$SCRIPT" register --type dataset --name customers --level N2
  [ "$status" -eq 0 ]
  run python3 "$SCRIPT" list --type dataset
  [ "$status" -eq 0 ]
  [[ "$output" == *"customers"* ]]
}

@test "register invalid level rejected (exit 2)" {
  run python3 "$SCRIPT" register --type dataset --name x --level N9
  [ "$status" -eq 2 ]
}

@test "register invalid type rejected (exit 2)" {
  run python3 "$SCRIPT" register --type bogus --name x --level N1
  [ "$status" -eq 2 ]
}

@test "asset without declared level is refused by required flag (argparse)" {
  run python3 "$SCRIPT" register --type dataset --name orphan
  [ "$status" -ne 0 ]
}

# ── lineage ─────────────────────────────────────────────────────────────

@test "lineage: dataset -> feature -> model 3 nodes with level guard" {
  python3 "$SCRIPT" register --type dataset --name raw_crops --level N2
  python3 "$SCRIPT" register --type feature --name yield_moisture --level N2 \
    --from-name raw_crops --from-type dataset --relation feeds
  python3 "$SCRIPT" register --type model --name yield_model --level N2 \
    --from-name yield_moisture --from-type feature --relation trained_on
  run python3 "$SCRIPT" lineage --name yield_model
  [ "$status" -eq 0 ]
  [[ "$output" == *"feeds"* ]]
  [[ "$output" == *"raw_crops"* ]]
}

@test "strict level guard rejects N1 -> N3 chain (exit 3)" {
  python3 "$SCRIPT" register --type dataset --name public_map --level N1
  run python3 "$SCRIPT" register --type model --name risky --level N3 \
    --from-name public_map --from-type dataset --relation trained_on
  [ "$status" -eq 3 ]
}

@test "lineage source not found -> exit 1" {
  python3 "$SCRIPT" register --type feature --name f1 --level N2
  run python3 "$SCRIPT" register --type model --name m1 --level N2 \
    --from-name missing --from-type dataset --relation trained_on
  [ "$status" -eq 1 ]
}

@test "show returns 1 for unknown asset" {
  run python3 "$SCRIPT" show --name nope
  [ "$status" -eq 1 ]
}
# ── Comportamiento: contenido real de las filas, lineage, guardas y salidas ──

reg() { python3 "$SCRIPT" register "$@"; }

@test "register imprime 'registered: tipo:nombre (level=…)' y show devuelve la fila completa" {
  run reg --type dataset --name ventas --level N3 --project alfa --source data/ventas.csv
  [ "$status" -eq 0 ]
  [ "$output" = "registered: dataset:ventas (level=N3)" ]
  run python3 "$SCRIPT" show --name ventas
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '1\tventas\tdataset\tN3\talfa\tdata/ventas.csv')" ]
}

@test "show de un activo sin proyecto ni origen deja esas columnas vacías" {
  reg --type report --name informe --level N1 > /dev/null
  run python3 "$SCRIPT" show --name informe
  [ "$output" = "$(printf '1\tinforme\treport\tN1\t\t')" ]
}

@test "register rechazado no deja nada: tipo o nivel inválidos no crean fila" {
  run reg --type bogus --name x --level N1
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid type 'bogus'"* ]]
  run reg --type dataset --name x --level N9
  [ "$status" -eq 2 ]
  [[ "$output" == *"invalid level 'N9'"* ]]
  run python3 "$SCRIPT" list
  [ "$status" -eq 1 ]
}

@test "los cuatro niveles N1 N2 N3 N4b y los cuatro tipos se aceptan" {
  local lv ty
  for lv in N1 N2 N3 N4b; do
    run reg --type dataset --name "d-$lv" --level "$lv"
    [ "$status" -eq 0 ]
  done
  for ty in dataset feature model report; do
    run reg --type "$ty" --name "t-$ty" --level N1
    [ "$status" -eq 0 ]
  done
  [ "$(python3 "$SCRIPT" list | wc -l)" -eq 8 ]
}

@test "list filtra por tipo, por nivel y por ambos; sin coincidencias sale 1 sin imprimir" {
  reg --type dataset --name a --level N1 > /dev/null
  reg --type dataset --name b --level N2 > /dev/null
  reg --type model --name c --level N2 > /dev/null
  run python3 "$SCRIPT" list --type dataset
  [ "$(echo "$output" | wc -l)" -eq 2 ]
  [[ "$output" != *"model"* ]]
  run python3 "$SCRIPT" list --level N2
  [ "$(echo "$output" | wc -l)" -eq 2 ]
  [[ "$output" != *$'\ta\t'* ]]
  run python3 "$SCRIPT" list --type model --level N2
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" == *$'\tc\tmodel\tN2'* ]]
  run python3 "$SCRIPT" list --type report
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

@test "show --name con --type separa activos homónimos de distinto tipo" {
  reg --type dataset --name clon --level N1 > /dev/null
  reg --type model --name clon --level N2 > /dev/null
  run python3 "$SCRIPT" show --name clon
  [ "$(echo "$output" | wc -l)" -eq 2 ]
  run python3 "$SCRIPT" show --name clon --type model
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" == *$'\tmodel\tN2'* ]]
  run python3 "$SCRIPT" show --name clon --type report
  [ "$status" -eq 1 ]
}

@test "registrar de nuevo el mismo nombre y tipo reemplaza el nivel (no duplica)" {
  reg --type dataset --name d --level N1 > /dev/null
  reg --type dataset --name d --level N4b > /dev/null
  run python3 "$SCRIPT" list
  [ "$(echo "$output" | wc -l)" -eq 1 ]
  [[ "$output" == *$'\tN4b\t'* ]]
}

@test "lineage: aguas arriba con '<-', aguas abajo con '->', relación y nivel visibles" {
  reg --type dataset --name raw --level N2 > /dev/null
  reg --type feature --name feat --level N2 --from-name raw --from-type dataset --relation feeds > /dev/null
  reg --type model --name mod --level N2 --from-name feat --from-type feature --relation trained_on > /dev/null
  run python3 "$SCRIPT" lineage --name feat
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "lineage: feature:feat" ]
  [[ "${lines[1]}" == "  <- feeds"*"dataset:raw (N2) [1hop]" ]]
  [[ "${lines[2]}" == "  -> trained_on"*"model:mod (N2) [1hop]" ]]
  [ "${#lines[@]}" -eq 3 ]
}

@test "lineage transitivo: 2 saltos con profundidad, y orden por profundidad" {
  reg --type dataset --name raw --level N2 > /dev/null
  reg --type feature --name feat --level N2 --from-name raw --from-type dataset --relation feeds > /dev/null
  reg --type model --name mod --level N2 --from-name feat --from-type feature --relation trained_on > /dev/null
  run python3 "$SCRIPT" lineage --name mod
  [[ "${lines[1]}" == *"feature:feat (N2) [1hop]" ]]
  [[ "${lines[2]}" == *"dataset:raw (N2) [2hop]" ]]
  run python3 "$SCRIPT" lineage --name raw
  [[ "${lines[1]}" == *"feature:feat (N2) [1hop]" ]]
  [[ "${lines[2]}" == *"model:mod (N2) [2hop]" ]]
}

@test "lineage está acotado a 3 saltos" {
  reg --type dataset --name n0 --level N2 > /dev/null
  reg --type dataset --name n1 --level N2 --from-name n0 --from-type dataset --relation feeds > /dev/null
  reg --type dataset --name n2 --level N2 --from-name n1 --from-type dataset --relation feeds > /dev/null
  reg --type dataset --name n3 --level N2 --from-name n2 --from-type dataset --relation feeds > /dev/null
  reg --type dataset --name n4 --level N2 --from-name n3 --from-type dataset --relation feeds > /dev/null
  run python3 "$SCRIPT" lineage --name n4
  [[ "$output" == *"dataset:n1 (N2) [3hop]"* ]]
  [[ "$output" != *"dataset:n0"* ]]
}

@test "lineage de un activo sin relaciones imprime solo la cabecera; desconocido sale 1" {
  reg --type dataset --name solo --level N1 > /dev/null
  run python3 "$SCRIPT" lineage --name solo
  [ "$status" -eq 0 ]
  [ "$output" = "lineage: dataset:solo" ]
  run python3 "$SCRIPT" lineage --name no-existe
  [ "$status" -eq 1 ]
  run python3 "$SCRIPT" lineage --name solo --type model
  [ "$status" -eq 1 ]
}

@test "lineage --type desambigua homónimos" {
  reg --type dataset --name clon --level N1 > /dev/null
  reg --type model --name clon --level N1 --from-name clon --from-type dataset --relation trained_on > /dev/null
  run python3 "$SCRIPT" lineage --name clon --type model
  [ "${lines[0]}" = "lineage: model:clon" ]
  [[ "${lines[1]}" == *"<- trained_on"*"dataset:clon"* ]]
  run python3 "$SCRIPT" lineage --name clon --type dataset
  [ "${lines[0]}" = "lineage: dataset:clon" ]
  [[ "${lines[1]}" == *"-> trained_on"*"model:clon"* ]]
}

@test "guarda de niveles: de menor a mayor sensibilidad se rechaza (N1->N2, N2->N3, N1->N4b, N3->N4b)" {
  reg --type dataset --name a1 --level N1 > /dev/null
  reg --type dataset --name a2 --level N2 > /dev/null
  reg --type dataset --name a3 --level N3 > /dev/null
  run reg --type model --name m --level N2 --from-name a1 --from-type dataset --relation feeds
  [ "$status" -eq 3 ]
  [[ "$output" == *"N1 -> N2 rejected"* ]]
  run reg --type model --name m --level N3 --from-name a2 --from-type dataset --relation feeds
  [ "$status" -eq 3 ]
  run reg --type model --name m --level N4b --from-name a1 --from-type dataset --relation feeds
  [ "$status" -eq 3 ]
  run reg --type model --name m --level N4b --from-name a3 --from-type dataset --relation feeds
  [ "$status" -eq 3 ]
}

@test "guarda de niveles: mismo nivel o hacia abajo se acepta (N3->N3, N3->N2, N4b->N1)" {
  reg --type dataset --name a3 --level N3 > /dev/null
  reg --type dataset --name a4 --level N4b > /dev/null
  run reg --type model --name m1 --level N3 --from-name a3 --from-type dataset --relation feeds
  [ "$status" -eq 0 ]
  run reg --type model --name m2 --level N2 --from-name a3 --from-type dataset --relation feeds
  [ "$status" -eq 0 ]
  run reg --type report --name r --level N1 --from-name a4 --from-type dataset --relation used_in
  [ "$status" -eq 0 ]
}

@test "un rechazo de la guarda no deja el activo registrado" {
  reg --type dataset --name publico --level N1 > /dev/null
  run reg --type model --name riesgo --level N3 --from-name publico --from-type dataset --relation trained_on
  [ "$status" -eq 3 ]
  run python3 "$SCRIPT" show --name riesgo
  [ "$status" -eq 1 ]
}

@test "SAVIA_CATALOG_STRICT=0 desactiva la guarda de niveles" {
  reg --type dataset --name publico --level N1 > /dev/null
  SAVIA_CATALOG_STRICT=0 run python3 "$SCRIPT" register --type model --name riesgo --level N3 \
    --from-name publico --from-type dataset --relation trained_on
  [ "$status" -eq 0 ]
  run python3 "$SCRIPT" lineage --name riesgo
  [[ "$output" == *"<- trained_on"*"dataset:publico (N1)"* ]]
}

@test "origen inexistente: exit 1, mensaje que nombra el origen y el activo no se crea" {
  run reg --type model --name m --level N2 --from-name fantasma --from-type dataset --relation feeds
  [ "$status" -eq 1 ]
  [[ "$output" == *"source asset 'fantasma' not found"* ]]
  run python3 "$SCRIPT" show --name m
  [ "$status" -eq 1 ]
}

@test "origen con el tipo equivocado no se encuentra" {
  reg --type dataset --name d --level N2 > /dev/null
  run reg --type model --name m --level N2 --from-name d --from-type feature --relation feeds
  [ "$status" -eq 1 ]
  run reg --type model --name m --level N2 --from-name d --relation feeds
  [ "$status" -eq 1 ]
}

@test "relación inválida la rechaza argparse (exit 2) sin crear el activo" {
  reg --type dataset --name d --level N2 > /dev/null
  run reg --type model --name m --level N2 --from-name d --from-type dataset --relation inventada
  [ "$status" -eq 2 ]
  run python3 "$SCRIPT" show --name m
  [ "$status" -eq 1 ]
}

@test "--relation sin --from-name registra el activo sin arista" {
  reg --type dataset --name d --level N2 > /dev/null
  run reg --type model --name m --level N2 --relation feeds
  [ "$status" -eq 0 ]
  run python3 "$SCRIPT" lineage --name m
  [ "$output" = "lineage: model:m" ]
}

@test "--db explícito gana a la variable de entorno" {
  local other="$BATS_TEST_TMPDIR/otra.db"
  python3 "$SCRIPT" --db "$other" register --type dataset --name aparte --level N1 > /dev/null
  [ -f "$other" ]
  run python3 "$SCRIPT" show --name aparte
  [ "$status" -eq 1 ]
  run python3 "$SCRIPT" --db "$other" show --name aparte
  [ "$status" -eq 0 ]
}

@test "sin subcomando falla con exit 2; subcomando desconocido también" {
  run python3 "$SCRIPT"
  [ "$status" -eq 2 ]
  run python3 "$SCRIPT" borrar
  [ "$status" -eq 2 ]
}

@test "la base se crea con directorios intermedios" {
  python3 "$SCRIPT" --db "$BATS_TEST_TMPDIR/a/b/c.db" register --type dataset --name d --level N1 > /dev/null
  [ -f "$BATS_TEST_TMPDIR/a/b/c.db" ]
}

@test "la base de datos tiene las tablas de catálogo y de lineage" {
  reg --type dataset --name d --level N1 > /dev/null
  run python3 -c "
import sqlite3,sys
c = sqlite3.connect('$TMP_DB')
t = {r[0] for r in c.execute(\"select name from sqlite_master where type='table'\")}
assert {'catalog_assets','catalog_lineage'} <= t, t
print('ok')"
  [ "$output" = "ok" ]
}

@test "argumentos obligatorios: register sin --type, --name o --level sale 2 sin crear nada; lineage sin --name también" {
  run python3 "$SCRIPT" register --name x --level N1
  [ "$status" -eq 2 ]
  [[ "$output" == *"required: --type"* ]]
  run python3 "$SCRIPT" register --type dataset --level N1
  [ "$status" -eq 2 ]
  [[ "$output" == *"required: --name"* ]]
  run python3 "$SCRIPT" register --type dataset --name x
  [ "$status" -eq 2 ]
  [[ "$output" == *"required: --level"* ]]
  run python3 "$SCRIPT" lineage
  [ "$status" -eq 2 ]
  [[ "$output" == *"required: --name"* ]]
  run python3 "$SCRIPT" list
  [ "$status" -eq 1 ]
}
