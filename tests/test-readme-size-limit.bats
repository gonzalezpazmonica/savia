#!/usr/bin/env bats
# Los README (y sus traducciones) respetan el máximo de 150 líneas y los enlaces a docs/readme resuelven.

setup() { cd "$BATS_TEST_DIRNAME/.."; ROOT="$PWD"; }

@test "todos los README raíz tienen 150 líneas o menos" {
  for f in README*.md; do
    n=$(wc -l < "$f")
    [ "$n" -le 150 ] || { echo "$f: $n líneas"; return 1; }
  done
}

@test "el check de compliance acepta README.md y README.en.md" {
  run bash .claude/compliance/checks/check-readme-sync.sh README.md README.en.md
  [ "$status" -eq 0 ]
}

@test "el check de compliance rechaza un README de más de 150 líneas" {
  cd "$BATS_TEST_TMPDIR"
  seq 1 151 > README.md
  run bash "$ROOT/.claude/compliance/checks/check-readme-sync.sh" README.md
  [ "$status" -eq 1 ]
}

@test "el check de compliance acepta exactamente 150 líneas (caso límite)" {
  cd "$BATS_TEST_TMPDIR"
  seq 1 150 > README.md
  run bash "$ROOT/.claude/compliance/checks/check-readme-sync.sh" README.md
  [ "$status" -eq 0 ]
}

@test "los enlaces a docs/readme de cada README resuelven" {
  for f in README*.md; do
    for t in $(grep -oP '\]\(\Kdocs/readme/[^)#]+' "$f"); do
      [ -f "$t" ] || { echo "$f -> $t no existe"; return 1; }
    done
  done
}

@test "los ficheros movidos conservan el contenido (tabla de capacidades y árbol)" {
  grep -q 'Spec-Driven Development' docs/readme/capabilities.es.md
  grep -q 'CLAUDE.md' docs/readme/repo-structure.en.md
}

@test "la línea canónica de contadores sigue en README.md" {
  grep -qP '\d+ comandos · \d+ agentes · \d+ skills · \d+ hooks' README.md
}
