#!/usr/bin/env bats
# SCL-002 — Cúpula de aprendizaje SaviaLearning: persistencia real cross-instancia
# Ref: docs/specs/SCL-002-cupula-aprendizaje.spec.md

set -uo pipefail

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

setup() {
  PERSIST="$REPO_ROOT/scripts/learning-persist.sh"
  FED="$REPO_ROOT/scripts/learning-federate.sh"
  PROP="$REPO_ROOT/scripts/learning-proposal.sh"
  SCHEMA="$REPO_ROOT/projects/savia-vaults/schema/entities/learning_proposal.yaml"
  TMPD="$(mktemp -d -t scl-s2-XXXXXX)"
  mkdir -p "$TMPD/vault/learning" "$TMPD/proposals"
  export SCL_VAULT_DIR="$TMPD/vault"
  export SCL_PROPOSALS_DIR="$TMPD/proposals"
}

teardown() {
  [ -n "${TMPD:-}" ] && rm -rf "$TMPD"
}

@test "AC-1: schema learning_proposal.yaml existe y declara type + propiedades requeridas" {
  [ -f "$SCHEMA" ]
  grep -q "^type: learning_proposal" "$SCHEMA"
  grep -q "^  id:" "$SCHEMA"
  grep -q "^  provenance:" "$SCHEMA"
  grep -q "^  lifecycle:" "$SCHEMA"
  grep -q "human_authored" "$SCHEMA"
  grep -q "INFERRED" "$SCHEMA"
  grep -q "^  criterion_id:" "$SCHEMA"
}

@test "SCL-008 TS-09: criterion_id survives persistence and federation without elevation" {
  echo "ev" > "$TMPD/ev.txt"
  bash "$PROP" --origin "o" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target criterio --criterion-id CRIT-034 --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  id=$(grep -m1 '^id:' "$f" | sed 's/^id: //')
  bash "$PERSIST" --file "$f" >/dev/null
  grep -q '^  criterion_id: CRIT-034' "$TMPD/vault/learning/${id}.md"
  bash "$FED" --import "$id" --output-dir "$TMPD/imported" >/dev/null
  grep -q '^criterion_id: CRIT-034' "$TMPD/imported/${id}.md"
  grep -q '^provenance: INFERRED' "$TMPD/imported/${id}.md"
  grep -q '^lifecycle: proposed' "$TMPD/imported/${id}.md"
}

@test "AC-2: learning-persist escribe la nota en la cúpula con entity+relations" {
  echo "ev" > "$TMPD/ev.txt"
  bash "$PROP" --origin "o" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target criterio --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  id=$(grep -m1 '^id:' "$f" | sed 's/^id: //')
  run bash "$PERSIST" --file "$f"
  [ "$status" -eq 0 ]
  [ -f "$TMPD/vault/learning/${id}.md" ]
  grep -q "type: learning_proposal" "$TMPD/vault/learning/${id}.md"
  grep -q "PROPOSES_CHANGE" "$TMPD/vault/learning/${id}.md"
  grep -q "EVIDENCE_FROM" "$TMPD/vault/learning/${id}.md"
}

@test "AC-3: persistencia idempotente — misma propuesta no duplica en la cúpula" {
  echo "ev" > "$TMPD/ev.txt"
  bash "$PROP" --origin "o" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target criterio --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  bash "$PERSIST" --file "$f" >/dev/null
  run bash "$PERSIST" --file "$f"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALREADY"* ]]
  count=$(ls "$TMPD/vault/learning/"*.md | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "AC-4: learning-federate lista lecciones disponibles en la cúpula" {
  echo "ev" > "$TMPD/ev.txt"
  bash "$PROP" --origin "o" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target skill --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  bash "$PERSIST" --file "$f" >/dev/null
  run bash "$FED" --list
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "lecciones aprendidas"
  echo "$output" | grep -q "LP-"
}

@test "AC-5: federacion importa leccion de la cupula como propuesta INFERRED local" {
  echo "ev" > "$TMPD/ev.txt"
  bash "$PROP" --origin "leccion federable" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target memoria --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  id=$(grep -m1 '^id:' "$f" | sed 's/^id: //')
  bash "$PERSIST" --file "$f" >/dev/null
  # importar en un output-dir local distinto
  run bash "$FED" --import "$id" --output-dir "$TMPD/imported"
  [ "$status" -eq 0 ]
  [ -f "$TMPD/imported/${id}.md" ]
  grep -q "^provenance: INFERRED" "$TMPD/imported/${id}.md"
  grep -q "^federated: true" "$TMPD/imported/${id}.md"
  grep -q "^lifecycle: proposed" "$TMPD/imported/${id}.md"
  grep -q "source_dome: SaviaLearning" "$TMPD/imported/${id}.md"
}

@test "AC-6: federacion no duplica importaciones (idempotente)" {
  echo "ev" > "$TMPD/ev.txt"
  bash "$PROP" --origin "o" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target spec --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" >/dev/null
  f=$(ls "$TMPD/proposals/"*.md)
  id=$(grep -m1 '^id:' "$f" | sed 's/^id: //')
  bash "$PERSIST" --file "$f" >/dev/null
  bash "$FED" --import "$id" --output-dir "$TMPD/imported" >/dev/null
  run bash "$FED" --import "$id" --output-dir "$TMPD/imported"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ALREADY"* ]]
  count=$(ls "$TMPD/imported/"*.md | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

@test "AC-7: learning-proposal --persist persiste automaticamente en la cupula" {
  echo "ev" > "$TMPD/ev.txt"
  run bash "$PROP" --origin "o" --evidence "$TMPD/ev.txt" --diagnosis "d" --change "c" \
    --target criterio --output-dir "$TMPD/proposals" --graph-index "$TMPD/g.jsonl" --persist
  [ "$status" -eq 0 ]
  [[ "$output" == *"persisted: true"* ]]
  count=$(ls "$TMPD/vault/learning/"*.md | wc -l | tr -d ' ')
  [ "$count" = "1" ]
}

# --- S03c: contrato de learning-persist.sh (SCL-002) ---

mk_prop() {
  # $1 = diagnóstico, $2 = cambio, $3 = target, $4 = evidencia (contenido)
  echo "${4:-ev-default}" > "$TMPD/ev.txt"
  find "$TMPD/proposals" -name '*.md' -delete
  bash "$PROP" --origin "origen de prueba" --evidence "$TMPD/ev.txt" --diagnosis "${1:-diag}" \
    --change "${2:-cambio}" --target "${3:-criterio}" --output-dir "$TMPD/proposals" \
    --graph-index "$TMPD/g.jsonl" >/dev/null
  PF=$(ls "$TMPD"/proposals/*.md | head -1)
  PID=$(grep -m1 '^id:' "$PF" | sed 's/^id: //')
}

@test "persist: la nota lleva frontmatter con procedencia INFERRED y ciclo proposed" {
  mk_prop
  run bash "$PERSIST" --file "$PF"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^PERSISTED: learning/$PID.md$"
  note="$TMPD/vault/learning/$PID.md"
  grep -q '^  provenance: INFERRED$' "$note"
  grep -q '^  lifecycle: proposed$' "$note"
  grep -q '^confidentiality: N2$' "$note"
  grep -q "^tags: \[scl, learning, criterio, " "$note"
}

@test "persist: segunda ejecución con la misma evidencia → exit 1 ALREADY y nota intacta" {
  mk_prop
  bash "$PERSIST" --file "$PF" >/dev/null
  before=$(sha256sum "$TMPD/vault/learning/$PID.md" | cut -d' ' -f1)
  run bash "$PERSIST" --file "$PF"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q "^ALREADY: $PID"
  [ "$(sha256sum "$TMPD/vault/learning/$PID.md" | cut -d' ' -f1)" = "$before" ]
}

@test "persist: --dry-run no escribe nada" {
  mk_prop
  run bash "$PERSIST" --file "$PF" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^DRY-RUN: persistiria en learning/$PID.md"
  [ ! -e "$TMPD/vault/learning/$PID.md" ]
}

@test "persist: sin --file → exit 2 con uso" {
  run bash "$PERSIST"
  [ "$status" -eq 2 ]
}

@test "persist: propuesta inexistente → exit 3" {
  run bash "$PERSIST" --file "$TMPD/no-existe.md"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "proposal not found"
}

@test "persist: vault inexistente → exit 3 sin crearlo" {
  mk_prop
  run bash "$PERSIST" --file "$PF" --vault "$TMPD/no-vault"
  [ "$status" -eq 3 ]
  [ ! -d "$TMPD/no-vault" ]
}

@test "persist: propuesta sin id (vacía) → exit 3" {
  : > "$TMPD/vacia.md"
  run bash "$PERSIST" --file "$TMPD/vacia.md"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q "missing id"
}

@test "persist: relaciones del grafo apuntan al target y al hash de evidencia" {
  mk_prop d c skill evidencia-xyz
  bash "$PERSIST" --file "$PF" >/dev/null
  note="$TMPD/vault/learning/$PID.md"
  h=$(grep -m1 '^evidence_hash: ' "$PF" | sed 's/^evidence_hash: //')
  [ -n "$h" ]
  grep -q '^  - type: PROPOSES_CHANGE$' "$note"
  grep -qE '^    target: skill$' "$note"
  grep -q "^    target: $h$" "$note"
  grep -qF "[[learning/$PID]]" "$note"
}

@test "persist: el cuerpo conserva diagnóstico y cambio propuestos" {
  mk_prop "causa raíz del ruido" "exigir diagnóstico no vacío" criterio
  bash "$PERSIST" --file "$PF" >/dev/null
  note="$TMPD/vault/learning/$PID.md"
  sed -n '/^## Diagnóstico/,/^## Cambio propuesto/p' "$note" | grep -q "causa raíz del ruido"
  sed -n '/^## Cambio propuesto/,/^## Origen/p' "$note" | grep -q "exigir diagnóstico no vacío"
}

@test "persist: dos propuestas distintas producen dos notas independientes" {
  mk_prop d1 c1 criterio ev-uno; id1="$PID"
  bash "$PERSIST" --file "$PF" >/dev/null
  mk_prop d2 c2 criterio ev-dos; id2="$PID"
  bash "$PERSIST" --file "$PF" >/dev/null
  [ "$id1" != "$id2" ]
  [ -f "$TMPD/vault/learning/$id1.md" ] && [ -f "$TMPD/vault/learning/$id2.md" ]
  if grep -q "$id2" "$TMPD/vault/learning/$id1.md"; then false; fi
}

@test "persist: --commit en vault que no es repo git avisa pero persiste (exit 0)" {
  mk_prop
  run bash "$PERSIST" --file "$PF" --commit
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "PERSISTED"
  [ -f "$TMPD/vault/learning/$PID.md" ]
}

@test "persist: --commit en vault git crea un commit con el id" {
  mk_prop
  git -C "$TMPD/vault" init -q
  git -C "$TMPD/vault" config user.email t@t.t
  git -C "$TMPD/vault" config user.name t
  run bash "$PERSIST" --file "$PF" --commit
  [ "$status" -eq 0 ]
  git -C "$TMPD/vault" log --format=%s -1 | grep -q "persist $PID"
}

@test "persist declara set -uo pipefail" {
  grep -q '^set -uo pipefail' "$PERSIST"
}
