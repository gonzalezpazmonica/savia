#!/usr/bin/env bats

setup() {
  PIPELINE="$BATS_TEST_DIRNAME/../scripts/kg-pipeline.sh"
  EXTRACTOR="$BATS_TEST_DIRNAME/../scripts/kg-extract.py"
  REPORT="$BATS_TEST_DIRNAME/../scripts/kg-quality-report.sh"
  CLEANUP="$BATS_TEST_DIRNAME/../scripts/kg-cleanup.sh"
  HOOK="$BATS_TEST_DIRNAME/../.claude/hooks/post-digestion-kg-extract.sh"
}

@test "pipeline exists and executable" {
  [ -f "$PIPELINE" ]
  [ -x "$PIPELINE" ]
}

@test "pipeline processes text input" {
  local tf
  tf=$(mktemp)
  echo "SE-291 and SE-288" > "$tf"
  run bash "$PIPELINE" "$tf"
  [ "$status" -eq 0 ]
  [[ "$output" == *"entity_count"* ]]
  rm -f "$tf"
}

@test "pipeline handles empty input" {
  local tf
  tf=$(mktemp)
  echo "" > "$tf"
  run bash "$PIPELINE" "$tf"
  [ "$status" -eq 0 ]
  rm -f "$tf"
}

@test "quality report script exists" {
  [ -f "$REPORT" ]
  [ -x "$REPORT" ]
}

@test "cleanup script exists" {
  [ -f "$CLEANUP" ]
  [ -x "$CLEANUP" ]
}

@test "hook exists and executable" {
  [ -f "$HOOK" ]
  [ -x "$HOOK" ]
}

@test "hook has set -uo pipefail" {
  head -3 "$HOOK" | grep -q "set -uo pipefail"
}

@test "policy doc exists" {
  [ -f "$BATS_TEST_DIRNAME/../docs/rules/domain/knowledge-graph-auto-extraction.md" ]
}

@test "pipeline quality-gate rejects non-verified entities" {
  local tf
  tf=$(mktemp)
  echo "The system uses patterns" > "$tf"
  run bash "$PIPELINE" "$tf"
  [ "$status" -eq 0 ]
  rm -f "$tf"
}

# ── Comportamiento con un extractor simulado (la tuberia se copia a un directorio temporal) ──

mkpipe() {
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P"
  cp "$PIPELINE" "$P/kg-pipeline.sh"
  ARGS="$BATS_TEST_TMPDIR/args"; STDIN_SEEN="$BATS_TEST_TMPDIR/stdin"
  cat > "$P/kg-extract.py" <<PYEOF
import sys
open("$ARGS","w").write(" ".join(sys.argv[1:]))
open("$STDIN_SEEN","w").write(sys.stdin.read())
sys.stderr.write("ruido del extractor\n")
print('{"extracted":true,"entity_count":2}')
PYEOF
}

@test "sin kg-extract.py: exit 2 y error JSON en stderr, nada en stdout" {
  P="$BATS_TEST_TMPDIR/p"; mkdir -p "$P"; cp "$PIPELINE" "$P/kg-pipeline.sh"
  echo "texto" > "$P/in.txt"
  run bash -c "bash '$P/kg-pipeline.sh' '$P/in.txt' 2>'$P/err'"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$(cat "$P/err")" = '{"error":"kg-extract.py not found"}' ]
}

@test "entrada vacia o solo espacios: extracted false sin llamar al extractor" {
  mkpipe
  for c in "" "   " $'\n\n  \n'; do
    printf '%s' "$c" > "$P/in.txt"
    run bash "$P/kg-pipeline.sh" "$P/in.txt"
    [ "$status" -eq 0 ]
    [ "$output" = '{"extracted":false,"reason":"empty input"}' ]
  done
  [ ! -e "$ARGS" ]
}

@test "fichero de entrada inexistente se trata como entrada vacia" {
  mkpipe
  run bash "$P/kg-pipeline.sh" "$P/no-existe.txt"
  [ "$status" -eq 0 ]
  [ "$output" = '{"extracted":false,"reason":"empty input"}' ]
  [ ! -e "$ARGS" ]
}

@test "con texto llama al extractor en modo deterministic con quality-gate y la fuente" {
  mkpipe
  echo "SE-291" > "$P/in.txt"
  run bash "$P/kg-pipeline.sh" "$P/in.txt" digest-reunion
  [ "$status" -eq 0 ]
  [ "$output" = '{"extracted":true,"entity_count":2}' ]
  [ "$(cat "$ARGS")" = "--mode deterministic --source digest-reunion --quality-gate" ]
}

@test "la fuente por defecto es unknown" {
  mkpipe
  echo "SE-291" > "$P/in.txt"
  run bash "$P/kg-pipeline.sh" "$P/in.txt"
  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = "--mode deterministic --source unknown --quality-gate" ]
}

@test "sin argumentos lee de stdin y el texto no vacio llega al extractor" {
  mkpipe
  run bash -c "echo 'texto por stdin' | bash '$P/kg-pipeline.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"extracted":true'* ]]
  run bash -c "echo '   ' | bash '$P/kg-pipeline.sh'"
  [[ "$output" == *'"reason":"empty input"'* ]]
}

@test "el stderr del extractor se descarta" {
  mkpipe
  echo "SE-291" > "$P/in.txt"
  run bash -c "bash '$P/kg-pipeline.sh' '$P/in.txt' 2>&1 >/dev/null"
  [ -z "$output" ]
}

@test "si el extractor falla, la tuberia responde error JSON y sale con 0" {
  mkpipe
  printf 'import sys\nsys.exit(3)\n' > "$P/kg-extract.py"
  echo "SE-291" > "$P/in.txt"
  run bash "$P/kg-pipeline.sh" "$P/in.txt"
  [ "$status" -eq 0 ]
  [ "$output" = '{"extracted":false,"error":"extraction failed"}' ]
}

@test "si el extractor falla despues de imprimir, se anade el JSON de error a lo ya emitido" {
  mkpipe
  printf 'import sys\nprint("parcial")\nsys.exit(1)\n' > "$P/kg-extract.py"
  echo "SE-291" > "$P/in.txt"
  run bash "$P/kg-pipeline.sh" "$P/in.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"parcial"* && "$output" == *'"error":"extraction failed"'* ]]
}

@test "el texto de entrada llega al extractor por stdin, desde fichero y desde stdin" {
  mkpipe
  printf 'linea uno\nlinea dos\n' > "$P/in.txt"
  run bash "$P/kg-pipeline.sh" "$P/in.txt" f </dev/null
  [ "$status" -eq 0 ]
  [ "$(cat "$STDIN_SEEN")" = $'linea uno\nlinea dos' ]
  run bash -c "printf 'desde pipe' | bash '$P/kg-pipeline.sh' - s"
  [ "$status" -eq 0 ]
  [ "$(cat "$STDIN_SEEN")" = "desde pipe" ]
}

@test "el extractor real devuelve JSON con entity_count para una referencia verificable" {
  tf="$BATS_TEST_TMPDIR/real.txt"; echo "SE-291 and SE-288" > "$tf"
  run bash "$PIPELINE" "$tf" prueba </dev/null
  [ "$status" -eq 0 ]
  python3 -c 'import json,sys;d=json.loads(sys.argv[1]);assert d["entity_count"]>=2,d' "$output"
}
