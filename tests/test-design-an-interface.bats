#!/usr/bin/env bats
# audit: score=90 hash=be37b431 date=2026-10-03
# test-design-an-interface.bats — SE-376: calibración de la skill design-an-interface
# contra lo que ejecuta de verdad.
#
# La skill es prosa (diseño con 3 sub-agentes), pero su contrato depende de tres
# piezas ejecutables: el hook de memoria (scripts/memory-store.sh save), el puente
# a SE-074 (scripts/parallel-specs-orchestrator.sh) y el índice de propuestas
# (scripts/propuestas-index-gen.sh --check, gate de validate-ci-local) cuando la
# salida se escribe en docs/propuestas/. Estos tests extraen las órdenes literales
# de SKILL.md y las ejecutan en un directorio temporal.
#
# Ref: docs/propuestas/SE-087-design-an-interface-parallel.md
# Ref: docs/rules/domain/architectural-vocabulary.md

SCRIPT="scripts/parallel-specs-orchestrator.sh"
MEMORY="scripts/memory-store.sh"
INDEXGEN="scripts/propuestas-index-gen.sh"
SKILL=".claude/skills/design-an-interface/SKILL.md"

setup() {
  set -uo pipefail
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  cd "$REPO"
  TMP="$(mktemp -d)"
  export SAVIA_TEST_MODE=true SAVIA_EMBED_AUTOSTART=false
}

teardown() {
  cd /
  rm -rf "$TMP"
}

# Devuelve la primera orden `bash ...` documentada en SKILL.md que contiene $1,
# uniendo las líneas de continuación con barra invertida (la prosa no cuenta).
skill_cmd() {
  awk -v pat="$1" '
    !grab && index($0, pat) && $0 ~ /^[[:space:]]*`?bash / { grab=1 }
    grab { gsub(/`/, ""); line = line $0; if ($0 ~ /\\$/) { sub(/\\$/, "", line); next } print line; exit }
  ' "$SKILL"
}

# Crea una spec mínima de prueba en $1 con id $2.
fixture_spec() {
  printf -- '---\nid: %s\ntitle: Alternativa %s\nstatus: PROPOSED\neffort: S 1h\n---\n\n# %s\n' "$2" "$2" "$2" > "$1/$2-design.md"
}

@test "objetivos: los tres scripts que la skill usa declaran set -uo pipefail" {
  for f in "$SCRIPT" "$MEMORY" "$INDEXGEN"; do
    run grep -cE '^set -[eu]*uo pipefail' "$f"
    [ "$status" -eq 0 ]
    [ "$output" -ge 1 ]
  done
}

@test "memoria: la orden documentada guarda la decisión con tipo decision y topic estable" {
  cmd="$(skill_cmd 'memory-store.sh save')"
  [ -n "$cmd" ]
  cmd="${cmd//<modulo>/cache-store}"
  cmd="${cmd//<diseno elegido y por que>/Diseno C por Locality}"
  run env PROJECT_ROOT="$TMP" bash -c "$cmd"
  [ "$status" -eq 0 ]
  run python3 -c 'import json,sys; e=json.loads(open(sys.argv[1]).readline()); print(e["type"], e["topic_key"], e["source"])' "$TMP/output/.memory-store.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "decision decision/interface-design-cache-store user:explicit" ]
}

@test "memoria: reject sin --source, la versión antigua del hook fallaba (SE-072)" {
  run env PROJECT_ROOT="$TMP" bash "$MEMORY" save --type decision --title "interface design: cache-store" --content "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"--source required"* ]]
  [ ! -s "$TMP/output/.memory-store.jsonl" ]
}

@test "memoria: boundary, ruta con espacios y título con acentos guarda sin error" {
  root="$TMP/dir con espacios"
  mkdir -p "$root"
  run env PROJECT_ROOT="$root" bash "$MEMORY" save --type decision --title "interface design: caché de sesión" --content "C" --source user:explicit
  [ "$status" -eq 0 ]
  run grep -c '"type":"decision"' "$root/output/.memory-store.jsonl"
  [ "$output" -eq 1 ]
}

@test "memoria: repetir el guardado del mismo módulo revisa el topic en lugar de duplicarlo" {
  for c in "A" "C"; do
    run env PROJECT_ROOT="$TMP" bash "$MEMORY" save --type decision --title "interface design: cache-store" --content "Diseno $c" --source user:explicit
    [ "$status" -eq 0 ]
  done
  [[ "$output" == *"rev: 2"* ]]
}

@test "puente SE-074: la orden documentada planifica las tres alternativas como specs" {
  mkdir -p "$TMP/specs"
  for id in SE-901 SE-902 SE-903; do fixture_spec "$TMP/specs" "$id"; done
  cmd="$(skill_cmd 'parallel-specs-orchestrator.sh')"
  [ -n "$cmd" ]
  [[ "$cmd" == *"--dry-run"* ]]
  cmd="${cmd//<SPEC-A>/SE-901}"; cmd="${cmd//<SPEC-B>/SE-902}"; cmd="${cmd//<SPEC-C>/SE-903}"
  run env SPECS_DIR="$TMP/specs" PARALLEL_RUNS_DIR="$TMP/runs" WORKTREES_DIR="$TMP/wt" bash -c "$cmd"
  [ "$status" -eq 0 ]
  [[ "$output" == *"specs queued       : 3"* ]]
  [[ "$output" == *"DRY-RUN: no workers spawned."* ]]
  [ ! -d "$TMP/runs/SE-901" ]
}

@test "puente SE-074: error si se pasan nombres de diseño sin spec, no hay design tracks" {
  mkdir -p "$TMP/specs"
  run env SPECS_DIR="$TMP/specs" PARALLEL_RUNS_DIR="$TMP/runs" WORKTREES_DIR="$TMP/wt" \
    bash "$SCRIPT" --dry-run design-A design-B design-C
  [ "$status" -eq 1 ]
  [[ "$output" == *"spec not found: design-A"* ]]
}

@test "puente SE-074: empty, sin alternativas es error de uso" {
  run env SPECS_DIR="$TMP/specs" PARALLEL_RUNS_DIR="$TMP/runs" WORKTREES_DIR="$TMP/wt" bash "$SCRIPT" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"no specs to execute"* ]]
}

@test "salida en docs/propuestas: con frontmatter invalida el INDEX hasta regenerarlo" {
  p="$TMP/propuestas"; mkdir -p "$p"
  fixture_spec "$p" SE-901
  PROPUESTAS_DIR_OVERRIDE="$p" bash "$INDEXGEN" >/dev/null
  printf -- '---\ntitle: cache-store interface design\nstatus: PROPOSED\n---\n\n# Diseno\n' > "$p/cache-store-interface-design.md"
  run env PROPUESTAS_DIR_OVERRIDE="$p" bash "$INDEXGEN" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
  # La skill documenta la orden de regeneración; tras ejecutarla el gate pasa.
  cmd="$(skill_cmd 'propuestas-index-gen.sh')"
  [ -n "$cmd" ]
  run env PROPUESTAS_DIR_OVERRIDE="$p" bash -c "$cmd"
  [ "$status" -eq 0 ]
  run env PROPUESTAS_DIR_OVERRIDE="$p" bash "$INDEXGEN" --check
  [ "$status" -eq 0 ]
  run grep -c "cache-store-interface-design.md" "$p/INDEX.md"
  [ "$output" -eq 1 ]
}

@test "salida en docs/propuestas: zero frontmatter no entra en el INDEX ni lo invalida" {
  p="$TMP/propuestas"; mkdir -p "$p"
  fixture_spec "$p" SE-901
  PROPUESTAS_DIR_OVERRIDE="$p" bash "$INDEXGEN" >/dev/null
  printf '# Diseno sin frontmatter\n' > "$p/cache-store-interface-design.md"
  run env PROPUESTAS_DIR_OVERRIDE="$p" bash "$INDEXGEN" --check
  [ "$status" -eq 0 ]
}

@test "disparadores: cada /comando de la description resuelve a una skill o comando real" {
  desc="$(grep -m1 '^description:' "$SKILL")"
  triggers="$(grep -oE "'/[a-z0-9-]+'" <<<"$desc" | tr -d "'/")"
  [ -n "$triggers" ]
  for t in $triggers; do
    [ -f ".claude/skills/$t/SKILL.md" ] || [ -f ".claude/commands/$t.md" ] || { echo "disparador sin destino: /$t"; return 1; }
  done
}

@test "rutas: invalid ninguna, toda ruta citada sin comodín existe en el repo" {
  missing=0
  while IFS= read -r p; do
    [[ "$p" == *"<"* || "$p" == *"*"* ]] && continue
    [ -e "$p" ] || { echo "ruta inexistente: $p"; missing=$((missing + 1)); }
  done < <(grep -oE '`(docs|scripts|projects|\.opencode|\.claude)/[^` ]+`' "$SKILL" | tr -d '`' | sort -u)
  [ "$missing" -eq 0 ]
}

@test "sub-agentes: large, el agente architect que la skill propone existe en ambos frontends" {
  run grep -oE 'subagent_type[=:] *`?[a-z-]+' "$SKILL"
  [ "$status" -eq 0 ]
  agent="$(sed -E 's/.*[=:] *`?//' <<<"$output" | head -1)"
  [ -f ".claude/agents/$agent.md" ]
  [ -f ".opencode/agents/$agent.md" ]
}
