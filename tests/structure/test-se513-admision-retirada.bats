#!/usr/bin/env bats
# SE-513 retirada (decisión de la operadora, 2026-11-14, «conectar antes de construir»):
# la admisión duradera (S1 admisión, S2 promoción) y la cola SE-075 sobre la que se apoyaba
# (scripts/lib/task-queue.py) no tenían consumidor y se han retirado.
# Un test que no puede fallar no vale (SE-456): el detector tiene casos negativos propios.

setup() {
  REPO_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Nombres partidos: este fichero no se cita a sí mismo.
  QUEUE="task""-queue"
  QUEUE_PY="task""_queue"
  PRE="test-se""513-"
}

# Lista ficheros bajo $1 que referencian la cola o las pruebas retiradas.
# Sin directorio válido sale 2 (fail-closed).
# Este fichero queda excluido por nombre; .claude/context-cache es caché de sesión gitignored.
# Las specs y notas de planificación (docs/specs, docs/propuestas) conservan el texto como historia
# y quedan fuera de estos directorios.
consumers() {
  [ -d "$1" ] || return 2
  grep -rlIP --exclude-dir=node_modules --exclude-dir=target --exclude-dir=context-cache \
    --exclude=test-se513-admision-retirada.bats \
    -e "${QUEUE}\.py|lib/${QUEUE}|output/${QUEUE}|${QUEUE_PY}|test-${QUEUE}|${PRE}(admission|promotion)" "$1" || true
}

@test "la cola y sus pruebas ya no existen en el árbol" {
  [ ! -e "$REPO_DIR/scripts/lib/$QUEUE.py" ]
  [ ! -e "$REPO_DIR/tests/structure/test-$QUEUE.bats" ]
  [ ! -e "$REPO_DIR/tests/structure/${PRE}admission.bats" ]
  [ ! -e "$REPO_DIR/tests/structure/${PRE}promotion.bats" ]
}

@test "ningún script, hook, workflow, test ni regla referencia la cola retirada" {
  for d in scripts .claude .github .opencode tests docs/rules; do
    [ -d "$REPO_DIR/$d" ] || continue
    run consumers "$REPO_DIR/$d"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "el detector funciona: una llamada a la cola en un fixture se detecta" {
  mkdir -p "$BATS_TEST_TMPDIR/fx/scripts"
  printf 'python3 scripts/lib/%s.py admit q --text x --origin y\n' "$QUEUE" > "$BATS_TEST_TMPDIR/fx/scripts/llamador.sh"
  run consumers "$BATS_TEST_TMPDIR/fx"
  [[ "$output" == *"llamador.sh"* ]]
}

@test "el detector funciona: la variante con guion bajo, la ruta de datos y las pruebas se detectan" {
  mkdir -p "$BATS_TEST_TMPDIR/fx2/tests"
  printf 'import %s\n' "$QUEUE_PY" > "$BATS_TEST_TMPDIR/fx2/tests/uno.py"
  printf 'DB=output/%s/q.sqlite\n' "$QUEUE" > "$BATS_TEST_TMPDIR/fx2/tests/dos.sh"
  printf 'bats tests/structure/%sadmission.bats\n' "$PRE" > "$BATS_TEST_TMPDIR/fx2/tests/tres.sh"
  run consumers "$BATS_TEST_TMPDIR/fx2"
  [[ "$output" == *"uno.py"* ]]
  [[ "$output" == *"dos.sh"* ]]
  [[ "$output" == *"tres.sh"* ]]
}

@test "el detector no da falsos positivos con la prosa «cola de tareas»" {
  mkdir -p "$BATS_TEST_TMPDIR/fx3"
  printf 'Muestra la task queue en vivo\n' > "$BATS_TEST_TMPDIR/fx3/doc.md"
  run consumers "$BATS_TEST_TMPDIR/fx3"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "el detector falla cerrado: directorio inexistente no da verde" {
  run consumers "$BATS_TEST_TMPDIR/no-existe"
  [ "$status" -eq 2 ]
}

@test "la spec SE-513 consta RETIRED y conserva su texto" {
  f="$REPO_DIR/docs/specs/SE-513-admision-duradera-y-comprobacion-previa.spec.md"
  run grep -m1 '^status:' "$f"
  [ "$output" = "status: RETIRED" ]
  run grep -c 'Admisión duradera' "$f"
  [ "$output" -ge 1 ]
}

@test "el prototipo S0 de SE-513 y su prueba de coherencia siguen (no se retiran)" {
  [ -f "$REPO_DIR/docs/specs/assets/prototipo-SE-513.md" ]
  [ -f "$REPO_DIR/tests/test-prototypes-s0-consistency.bats" ]
}
