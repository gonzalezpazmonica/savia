#!/usr/bin/env bats
# SE-448 S0 — recuento de texto imperativo dirigido a agentes en documentos de terceros
S="scripts/se448/third-party-directives.py"
F="tests/fixtures/se448-third-party"

setup() { cd "$(dirname "$BATS_TEST_FILENAME")/../.."; }

@test "SE-448 S0: documentos con directivas se cuentan (2 de 2)" {
  run python3 $S --root $F/with-directive
  [ "$status" -eq 0 ]
  [[ "$output" == *"not_by_design files=2 with_directive=2"* ]]
  [[ "$output" == *"directive: $F/with-directive/notas.md"* ]]
}

@test "SE-448 S0: frase del AC9 cae en action-ban; override con URL en override y exfil" {
  run python3 $S --root $F/with-directive --json
  [ "$status" -eq 0 ]
  python3 - "$output" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); f={x["path"].split("/")[-1]:x["counts"] for x in d["per_file"]}
assert f["notas.md"]["action-ban"] >= 1, f
assert f["guia-en.md"]["override"] == 1 and f["guia-en.md"]["exfil"] == 1, f
PY
}

@test "SE-448 S0: negativo, documento sin texto imperativo = 0" {
  run python3 $S --root $F/clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"not_by_design files=1 with_directive=0"* ]]
  [[ "$output" != *"directive: "* ]]
}

@test "SE-448 S0: LICENSE no cuenta y SKILL.md se cuenta aparte (por diseño)" {
  run python3 $S --root $F/clean
  [[ "$output" == *"scanned_files=2"* ]]
  [[ "$output" == *"by_design files=1 with_directive=1"* ]]
}

@test "SE-448 S0: el texto dentro de bloques de código vallados no cuenta" {
  run python3 $S --root $F/fenced-only
  [[ "$output" == *"not_by_design files=1 with_directive=0"* ]]
}

@test "SE-448 S0: la salida no reproduce el texto de los documentos" {
  run python3 $S --root $F/with-directive --json
  [[ "$output" != *"evil.example"* ]]
  [[ "$output" != *"revisor B"* ]]
}

@test "SE-448 S0: raíz inexistente falla cerrado con código 2" {
  run python3 $S --root $F/no-existe
  [ "$status" -eq 2 ]
}
