#!/usr/bin/env bats
# Learning proposals: cuándo aplica y confianza (idea de harness2: una lección
# sin condición de uso ni evidencia no se puede verificar después).
# Ref: docs/rules/domain/remedy-ladder.md

set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LP="$REPO_ROOT/scripts/learning-proposal.sh"
  TMPD="$(mktemp -d -t lp-cue-XXXXXX)"
  printf 'evidencia de prueba\n' > "$TMPD/ev.md"
  export SCL_GRAPH_INDEX="$TMPD/graph.jsonl"
}

teardown() {
  [[ -n "${TMPD:-}" && -d "$TMPD" ]] && find "$TMPD" -mindepth 1 -delete && rmdir "$TMPD"
}

crear() {
  bash "$LP" --origin "origen" --evidence "$TMPD/ev.md" --diagnosis "diag" \
    --change "cambio" --target criterio --output-dir "$TMPD/out" "$@"
}

@test "cue y confianza quedan en frontmatter y cuerpo" {
  run crear --when "tareas de cúpula en headless" --confidence media
  [ "$status" -eq 0 ]
  f=$(ls "$TMPD"/out/LP-*.md)
  grep -q '^when: tareas de cúpula en headless$' "$f"
  grep -q '^confidence: media$' "$f"
  grep -q '^## Cuándo aplica$' "$f"
}

@test "confianza fuera de alta/media/baja es error de uso" {
  run crear --when "x" --confidence total
  [ "$status" -eq 2 ]
  [ ! -d "$TMPD/out" ] || [ -z "$(ls "$TMPD/out")" ]
}

@test "sin cue sigue funcionando y lo marca como pendiente" {
  run crear
  [ "$status" -eq 0 ]
  f=$(ls "$TMPD"/out/LP-*.md)
  grep -q '^when: *$' "$f"
  grep -q 'sin condición de uso declarada' "$f"
}

@test "evidencia inexistente sigue rechazándose" {
  run bash "$LP" --origin o --evidence "$TMPD/no-existe.md" --diagnosis d \
    --change c --target criterio --output-dir "$TMPD/out" --when x --confidence alta
  [ "$status" -eq 3 ]
}
