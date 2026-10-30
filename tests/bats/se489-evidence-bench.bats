#!/usr/bin/env bats
# SE-489 R1 — banco de evidencia de Vaults: esquema, validador, corpus y casos.
# Ref: projects/savia-vaults/eval/evidence-bench/README.md
SCRIPT="projects/savia-vaults/eval/evidence-bench/validate.py"

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  BENCH="$ROOT/projects/savia-vaults/eval/evidence-bench"
  V="$ROOT/$SCRIPT"
  TMPD="$(mktemp -d)"
  head -1 "$BENCH/cases.jsonl" > "$TMPD/one.jsonl"
}

teardown() {
  [[ -n "${TMPD:-}" && -d "$TMPD" ]] && find "$TMPD" -type f -delete && find "$TMPD" -depth -type d -empty -delete
}

# Valida un caso mutado con python; imprime los errores.
mutate() {
  python3 - "$BENCH" "$1" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import validate as v
cases = v.load_jsonl(sys.argv[1] + "/cases.jsonl")
man = json.load(open(sys.argv[1] + "/manifest.json"))
c = cases[0]
exec(sys.argv[2])
errs = v.validate([c], man, sys.argv[1] + "/../../../..", hidden=True)
print("\n".join(errs) or "VALID")
PY
}

@test "SE-489 R1: el banco versionado valida contra esquema y ficheros (302 casos)" {
  run python3 "$V"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK casos=302 errores=0"* ]]
}

@test "SE-489 R1: tests unitarios del corpus, del validador y del banco" {
  run python3 -m unittest discover -s "$BENCH/tests"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "SE-489 R1: manifest con snapshot y las tres cúpulas del banco" {
  run python3 -c "import json;m=json.load(open('$BENCH/manifest.json'));print(m['snapshot_commit'][:9], sorted(m['domes']))"
  [ "$status" -eq 0 ]
  [ "$output" = "c783d6bcf ['bench-legal', 'bench-restringida', 'savia-docs']" ]
}

@test "SE-489 R1: check_schema acepta un caso del banco tal cual" {
  run python3 -c "import sys,json;sys.path.insert(0,'$BENCH');import validate as v;c=v.load_jsonl('$TMPD/one.jsonl')[0];print(v.check_schema(c,json.load(open('$BENCH/schema.json'))))"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

@test "SE-489 R1: blob_sha coincide con git hash-object" {
  f="$BENCH/corpus/bench-legal/contratos/CT-2026-104/contrato.md"
  run python3 -c "import sys;sys.path.insert(0,'$BENCH');import validate as v;print(v.blob_sha(open('$f','rb').read()))"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$ROOT" hash-object "$f")" ]
}

@test "SE-489 R1: section_text y norm localizan la cita dentro de su cláusula" {
  run python3 -c "import sys;sys.path.insert(0,'$BENCH');import validate as v;t=open('$BENCH/corpus/bench-legal/contratos/CT-2026-104/contrato.md').read();s=v.section_text(t,'Cláusula 9. Garantía');print(v.norm(s))"
  [ "$status" -eq 0 ]
  [ "$output" = "Las condiciones de garantía de los trabajos se detallan en el Anexo IV." ]
}

@test "SE-489 R1 invalid: una revisión falsa hace fallar la validación con código 1" {
  sed 's/"revision": "[0-9a-f]\{40\}"/"revision": "0000000000000000000000000000000000000000"/' "$BENCH/cases.jsonl" > "$TMPD/bad.jsonl"
  run python3 "$V" --cases "$TMPD/bad.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"INVALID"*"revision"* ]]
}

@test "SE-489 R1 missing git: sin historial el validador cierra en fallo" {
  run python3 "$V" --repo "$TMPD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"snapshot_commit"* ]]
}

@test "SE-489 R1 reject: campo desconocido en un caso" {
  run mutate 'c["extra"] = 1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"campo no permitido extra"* ]]
}

@test "SE-489 R1 error: cita que no está en la sección declarada" {
  run mutate 'c["expected"]["required_evidence"][0]["locator"]["quote"] = "texto que no aparece en el documento"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"no está en la sección"* ]]
}

@test "SE-489 R1 boundary: max_unauthorized_reads distinto de cero se rechaza" {
  run mutate 'c["expected"]["max_unauthorized_reads"] = 1'
  [ "$status" -eq 0 ]
  [[ "$output" == *"max_unauthorized_reads: debe valer 0"* ]]
}

@test "SE-489 R1 null: as_of nulo en la categoría D se rechaza" {
  run mutate 'c["category"] = "D"; c["id"] = "D-999"; c["scope"]["as_of"] = None'
  [ "$status" -eq 0 ]
  [[ "$output" == *"exige scope.as_of"* ]]
}

@test "SE-489 R1 empty: fichero de casos vacío no cumple los mínimos" {
  : > "$TMPD/empty.jsonl"
  run python3 "$V" --cases "$TMPD/empty.jsonl"
  [ "$status" -eq 1 ]
  [[ "$output" == *"mínimo 50"* ]]
}

@test "SE-489 R1 nonexistent: fichero de casos inexistente es error de entrada (2)" {
  run python3 "$V" --cases "$TMPD/no-existe.jsonl"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR"* ]]
}
