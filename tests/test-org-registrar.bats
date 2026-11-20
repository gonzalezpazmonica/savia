#!/usr/bin/env bats
# SE-376 S03 — org-registrar: pruebas de comportamiento del validador, el índice y la consulta
# Ref: SE-365 (Company as Code), SE-352 (origin/source), docs/propuestas/SE-376-debt-budget.yaml
#
# org-registrar valida entidades de la organización antes de que entren en el grafo. Es un
# gate: una entidad inválida debe salir con 2 y nombrar el motivo, una válida con 0. Cada
# prueba construye entidades mínimas en un directorio temporal y comprueba un solo motivo
# de rechazo, para que el fallo de una regla no quede tapado por otra.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REG="$REPO_ROOT/scripts/org-registrar.py"
  WRAP="$REPO_ROOT/scripts/org-registrar.sh"
  TMP="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMP"
}

# ent <fichero> [clave=valor …]: entidad proyecto válida por defecto; una clave "sin:<campo>"
# la quita y "rel=<Tipo>:<target>" añade una relación.
ent() {
  local f="$1"; shift
  local id=ent-a type=project name="Entidad A" status=active origin=agent source=agent
  local extra="" rels="" omit=""
  for kv in "$@"; do
    case "$kv" in
      id=*) id="${kv#id=}" ;;
      type=*) type="${kv#type=}" ;;
      name=*) name="${kv#name=}" ;;
      status=*) status="${kv#status=}" ;;
      origin=*) origin="${kv#origin=}" ;;
      source=*) source="${kv#source=}" ;;
      sin:*) omit="$omit ${kv#sin:}" ;;
      rel=*) rels="$rels
  - { type: ${kv#rel=}"; ;;
      *) extra="$extra
${kv%%=*}: ${kv#*=}" ;;
    esac
  done
  mkdir -p "$(dirname "$f")"
  {
    echo "---"
    [[ " $omit " == *" id "* ]] || echo "id: $id"
    [[ " $omit " == *" type "* ]] || echo "type: $type"
    [[ " $omit " == *" name "* ]] || echo "name: $name"
    [[ " $omit " == *" status "* ]] || echo "status: $status"
    echo "origin: $origin"
    echo "source: $source"
    [[ -z "$extra" ]] || echo "${extra#$'\n'}"
    if [[ -n "$rels" ]]; then
      echo "relations:"
      # rels llega como "<Tipo>:<target>" por entrada
      for r in $(echo "$rels" | sed 's/^  - { type: //' | tr '\n' ' '); do
        echo "  - { type: ${r%%:*}, target: ${r#*:} }"
      done
    fi
    echo "---"
    echo "Cuerpo."
  } > "$f"
}

reg() { run python3 "$REG" "$@"; }

# ── validate: aceptación ─────────────────────────────────────────────────────

@test "validate: a complete entity is accepted with exit 0 and no errors" {
  ent "$TMP/a.md"
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["valid"], d["errors"])')" = "True []" ]
}

@test "validate: origin owner with source human is accepted" {
  ent "$TMP/a.md" origin=owner source=human
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 0 ]
}

# ── validate: cada regla de rechazo, de una en una ───────────────────────────

@test "validate: each missing mandatory field is rejected and named" {
  for f in id type name status; do
    ent "$TMP/a.md" "sin:$f"
    reg validate --file "$TMP/a.md"
    [ "$status" -eq 2 ]
    [[ "$output" == *"falta campo obligatorio: $f"* ]]
  done
}

@test "validate: an unknown type is rejected" {
  ent "$TMP/a.md" type=gadget
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"type inválido: gadget"* ]]
}

@test "validate: an unknown status is rejected" {
  ent "$TMP/a.md" status=zombie
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"status inválido: zombie"* ]]
}

@test "validate: a resource needs a known category, a project does not" {
  ent "$TMP/r.md" type=resource category=magic
  reg validate --file "$TMP/r.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"resource category inválida: magic"* ]]
  ent "$TMP/r.md" type=resource category=infra
  reg validate --file "$TMP/r.md"
  [ "$status" -eq 0 ]
  ent "$TMP/p.md" type=project category=magic
  reg validate --file "$TMP/p.md"
  [ "$status" -eq 0 ]
}

@test "validate: sensitivity secret is forbidden, other levels are not" {
  ent "$TMP/a.md" sensitivity=secret
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"sensitivity 'secret' prohibida"* ]]
  ent "$TMP/a.md" sensitivity=internal
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 0 ]
}

@test "validate: origin must be owner or agent" {
  ent "$TMP/a.md" origin=robot
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"origin inválido: robot"* ]]
}

@test "validate: origin owner without source human is rejected" {
  ent "$TMP/a.md" origin=owner source=agent
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"origin: owner requiere source: human"* ]]
}

@test "validate: a policy declared by an agent is rejected, by the owner it is accepted" {
  ent "$TMP/pol.md" type=policy origin=agent source=agent
  reg validate --file "$TMP/pol.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"solo puede declararlo origin: owner"* ]]
  ent "$TMP/pol.md" type=policy origin=owner source=human
  reg validate --file "$TMP/pol.md"
  [ "$status" -eq 0 ]
}

# ── validate: relaciones ─────────────────────────────────────────────────────

@test "validate: a relation outside the closed vocabulary is rejected" {
  ent "$TMP/a.md" "rel=Loves:ent-b"
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"relación no listada: Loves"* ]]
}

@test "validate: every relation of the vocabulary is accepted" {
  for r in BelongsToUnit ManagedBy AppliesTo ImplementsCriterio ImplementsSpec UsesResource UsedByProject OwnedByUnit GovernedByPolicy; do
    ent "$TMP/a.md" "rel=$r:ent-b"
    reg validate --file "$TMP/a.md"
    [ "$status" -eq 0 ]
  done
}

@test "validate: with --known-ids a dangling target is rejected, a known one accepted" {
  ent "$TMP/a.md" "rel=UsesResource:res-x"
  reg validate --file "$TMP/a.md" --known-ids "ent-a res-y"
  [ "$status" -eq 2 ]
  [[ "$output" == *"target inexistente: res-x"* ]]
  reg validate --file "$TMP/a.md" --known-ids "ent-a res-x"
  [ "$status" -eq 0 ]
}

@test "validate: without --known-ids targets are not checked" {
  ent "$TMP/a.md" "rel=UsesResource:res-nowhere"
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 0 ]
}

@test "validate: one bad relation among several is still caught" {
  ent "$TMP/a.md" "rel=UsesResource:res-x" "rel=Loves:res-y"
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"relación no listada: Loves"* ]]
}

# ── validate: entrada rota (fail-closed) ─────────────────────────────────────

@test "validate: a missing file is rejected, never treated as valid" {
  reg validate --file "$TMP/no-existe.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"archivo no existe"* ]]
}

@test "validate: a file without frontmatter is rejected" {
  printf 'solo texto, sin cabecera\n' > "$TMP/a.md"
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"frontmatter ausente o malformado"* ]]
}

@test "validate: an empty file is rejected" {
  : > "$TMP/a.md"
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
}

@test "validate: several errors are all reported, not just the first" {
  ent "$TMP/a.md" type=gadget status=zombie origin=robot
  reg validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
  [[ "$output" == *"type inválido"* ]]
  [[ "$output" == *"status inválido"* ]]
  [[ "$output" == *"origin inválido"* ]]
}

# ── index ────────────────────────────────────────────────────────────────────

@test "index: collects valid entities from nested folders with their relations" {
  ent "$TMP/d/a.md" id=ent-a "rel=UsesResource:res-x"
  ent "$TMP/d/sub/b.md" id=res-x type=resource category=tool
  reg index --dir "$TMP/d" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["count"], sorted(d["entities"]))')" = "2 ['ent-a', 'res-x']" ]
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["entities"]["ent-a"]["relations"][0]["target"])')" = "res-x" ]
}

@test "index: files starting with underscore, without frontmatter or with an unknown type are skipped" {
  ent "$TMP/d/a.md" id=ent-a
  ent "$TMP/d/_plantilla.md" id=ent-tpl
  printf 'README sin cabecera\n' > "$TMP/d/README.md"
  ent "$TMP/d/raro.md" id=ent-raro type=gadget
  ent "$TMP/d/sinid.md" "sin:id"
  reg index --dir "$TMP/d" --json
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["count"], sorted(d["entities"]))')" = "1 ['ent-a']" ]
}

@test "index: a missing directory gives zero entities, not an error" {
  reg index --dir "$TMP/no-existe" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(json.load(sys.stdin)["count"])')" = "0" ]
}

@test "index: without --json it prints the count in plain text" {
  ent "$TMP/d/a.md" id=ent-a
  ent "$TMP/d/b.md" id=ent-b
  reg index --dir "$TMP/d"
  [ "$output" = "indexado: 2 entidades" ]
}

# ── query ────────────────────────────────────────────────────────────────────

@test "query: uses_resource returns users through UsesResource and UsedByProject, not other relations" {
  ent "$TMP/d/p1.md" id=proj-1 "rel=UsesResource:res-x"
  ent "$TMP/d/res.md" id=res-y type=resource category=tool "rel=UsedByProject:res-x"
  ent "$TMP/d/p2.md" id=proj-2 "rel=OwnedByUnit:res-x"
  ent "$TMP/d/p3.md" id=proj-3 "rel=UsesResource:res-other"
  python3 "$REG" index --dir "$TMP/d" --json > "$TMP/graph.json"
  reg query --graph "$TMP/graph.json" --what uses_resource --id res-x
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(sorted(json.load(sys.stdin)))')" = "['proj-1', 'res-y']" ]
}

@test "query: a resource nobody uses gives an empty list" {
  ent "$TMP/d/p1.md" id=proj-1 "rel=UsesResource:res-x"
  python3 "$REG" index --dir "$TMP/d" --json > "$TMP/graph.json"
  reg query --graph "$TMP/graph.json" --what uses_resource --id res-zzz
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# ── propose (escritura mediada) ──────────────────────────────────────────────

@test "propose: a valid entity is copied unchanged to the proposals folder and the source stays" {
  ent "$TMP/a.md" id=ent-a
  cp "$TMP/a.md" "$TMP/a.orig"
  reg propose --file "$TMP/a.md" --out "$TMP/prop"
  [ "$status" -eq 0 ]
  [[ "$output" == *"requiere confirmación humana"* ]]
  cmp "$TMP/prop/a.md" "$TMP/a.orig"
  cmp "$TMP/a.md" "$TMP/a.orig"
}

@test "propose: an invalid entity exits 2 so it is never taken as ready" {
  ent "$TMP/a.md" type=gadget
  reg propose --file "$TMP/a.md" --out "$TMP/prop"
  [ "$status" -eq 2 ]
}

# ── envoltorio y CLI ─────────────────────────────────────────────────────────

@test "wrapper: org-registrar.sh passes arguments and the exit code through" {
  ent "$TMP/a.md"
  run bash "$WRAP" validate --file "$TMP/a.md"
  [ "$status" -eq 0 ]
  ent "$TMP/a.md" type=gadget
  run bash "$WRAP" validate --file "$TMP/a.md"
  [ "$status" -eq 2 ]
}

@test "wrapper: keeps set -uo pipefail" {
  grep -q '^set -uo pipefail' "$WRAP"
}

@test "cli: no subcommand prints help and exits 1, validate without --file exits non-zero" {
  reg
  [ "$status" -eq 1 ]
  reg validate
  [ "$status" -ne 0 ]
}
