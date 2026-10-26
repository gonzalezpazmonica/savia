#!/usr/bin/env bats
# test-se253-agent-sync.bats — SE-253 Slice 3: Agent sync guard
# AC-3.1: --check exits 0 in <5s with clean state
# AC-3.2: drift causes exit 1 naming the file
# AC-3.3: CI job exists
# AC-3.4: all single-side agents are in allowlist

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/scripts/agents-catalog-sync.sh"
ALLOWLIST="$REPO_ROOT/docs/agents-sync-allowlist.md"
CI_WORKFLOW="$REPO_ROOT/.github/workflows/ci.yml"

@test "AC-3.1: agents-catalog-sync.sh --check exists and is executable" {
  [ -f "$SYNC_SCRIPT" ]
  [ -x "$SYNC_SCRIPT" ]
}

@test "AC-3.1: --check with clean repo state exits 0" {
  run bash "$SYNC_SCRIPT" --check
  [ "$status" -eq 0 ]
}

@test "AC-3.1: --check completes in under 5 seconds" {
  start=$(date +%s%N 2>/dev/null || date +%s)
  run bash "$SYNC_SCRIPT" --check
  end=$(date +%s%N 2>/dev/null || date +%s)
  # Accept nanoseconds or seconds
  if [[ ${#start} -gt 10 ]]; then
    elapsed_ms=$(( (end - start) / 1000000 ))
    [ "$elapsed_ms" -lt 5000 ]
  else
    elapsed=$(( end - start ))
    [ "$elapsed" -lt 5 ]
  fi
}

@test "AC-3.1: --check reports PASS or VERDICT: PASS on clean state" {
  run bash "$SYNC_SCRIPT" --check
  [[ "$output" =~ PASS ]]
}

@test "AC-3.3: ci.yml exists" {
  [ -f "$CI_WORKFLOW" ]
}

@test "AC-3.3: ci.yml contains agents-catalog-sync --check reference" {
  grep -q "agents-catalog-sync" "$CI_WORKFLOW" || grep -q "agent.sync" "$CI_WORKFLOW"
}

@test "AC-3.4: allowlist file exists" {
  [ -f "$ALLOWLIST" ]
}

@test "AC-3.4: allowlist contains archive-digest (known single-side agent)" {
  grep -q "archive-digest" "$ALLOWLIST"
}

@test "AC-3.4: allowlist contains authority-claim-judge (known single-side agent)" {
  grep -q "authority-claim-judge" "$ALLOWLIST"
}

@test "AC-3.4: allowlist contains code-twin-agent (known single-side agent)" {
  grep -q "code-twin-agent" "$ALLOWLIST"
}

@test "AC-3.4: allowlist contains configurator (known single-side agent)" {
  grep -q "configurator" "$ALLOWLIST"
}

@test "AC-3.4: allowlist contains criterion-simulation-judge (known single-side agent)" {
  grep -q "criterion-simulation-judge" "$ALLOWLIST"
}

@test "AC-3.4: allowlist contains fiction-framing-judge (known single-side agent)" {
  grep -q "fiction-framing-judge" "$ALLOWLIST"
}

@test "AC-3.4: allowlist contains structural-framing-judge (known single-side agent)" {
  grep -q "structural-framing-judge" "$ALLOWLIST"
}

@test "AC-3.4: allowlist has a table header with required columns" {
  grep -q "| Agente" "$ALLOWLIST" || grep -q "| Agent" "$ALLOWLIST"
}

@test "AC-3.4: allowlist documents decision-trees/ subdirectory" {
  grep -q "decision-trees" "$ALLOWLIST"
}

@test "AC-3.4: allowlist documents references/ subdirectory" {
  grep -q "references/" "$ALLOWLIST" || grep -q "References" "$ALLOWLIST"
}

@test "AC-3.4: both .claude/agents and .opencode/agents dirs exist" {
  [ -d "$REPO_ROOT/.claude/agents" ]
  [ -d "$REPO_ROOT/.opencode/agents" ]
}

@test "AC-3.4: .claude/agents has at least 70 agent files" {
  count=$(ls "$REPO_ROOT/.claude/agents/"*.md 2>/dev/null | wc -l)
  [ "$count" -ge 70 ]
}

# ── Comportamiento aislado: arbol temporal con agentes propios ───────────────
mk_agents_tree() {
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts" "$T/agents" "$T/docs/rules/domain" "$T/apartado"
  cp "$SYNC_SCRIPT" "$T/scripts/agents-catalog-sync.sh"
  printf -- '---\nname: zeta-agent\nmodel_tier: heavy\ndescription: "Hace cosas | con barra"\n---\ncuerpo\n' > "$T/agents/zeta.md"
  printf -- '---\nname: alpha-agent\nmodel_tier: fast\ndescription: Primera\n---\n' > "$T/agents/alpha.md"
  printf -- '---\ndescription: sin nombre ni tier\n---\n' > "$T/agents/huerfano.md"
  S="$T/scripts/agents-catalog-sync.sh"
  CAT="$T/docs/rules/domain/agents-catalog.md"
  export AGENTS_DIR="$T/agents"
}

@test "sync aislado: --generate ordena, aplica fallback de nombre y tier y escapa la barra" {
  mk_agents_tree
  run bash "$S" --generate
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "| Agent | Tier | Description |" ]
  [ "${lines[1]}" = "|---|---|---|" ]
  # la descripcion arrastra un espacio final (newline->espacio); se normaliza
  [ "${lines[2]//  / }" = "| alpha-agent | fast | Primera |" ]
  [ "${lines[3]//  / }" = "| huerfano | (default) | sin nombre ni tier |" ]
  [ "${lines[4]//  / }" = '| zeta-agent | heavy | Hace cosas \| con barra |' ]
  [ "${#lines[@]}" -eq 5 ]
}

@test "sync aislado: --check sin catalogo falla con 1 y lo dice (texto y json)" {
  mk_agents_tree
  run bash "$S" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: catalog not found"* ]]
  run bash "$S" --check --json
  [ "$status" -eq 1 ]
  [ "$output" = '{"verdict":"FAIL","total_agents":3,"catalog_missing":true}' ]
}

@test "sync aislado: --apply escribe el catalogo y despues --check pasa" {
  mk_agents_tree
  run bash "$S" --apply
  [ "$status" -eq 0 ]
  [[ "$output" == "Applied: $CAT (3 agents)" ]]
  grep -q "Total: 3 agents" "$CAT"
  grep -q '^| zeta-agent | heavy |' "$CAT"
  run bash "$S" --check --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"verdict":"PASS","total_agents":3,"catalog_rows":3,"drift":0}' ]
  run bash "$S" --check
  [[ "$output" == *"VERDICT: PASS"* ]]
}

@test "sync aislado: anadir o quitar un agente produce drift con 1 y --apply lo corrige" {
  mk_agents_tree
  bash "$S" --apply >/dev/null
  printf -- '---\nname: nuevo\n---\n' > "$T/agents/nuevo.md"
  run bash "$S" --check --json
  [ "$status" -eq 1 ]
  [ "$output" = '{"verdict":"FAIL","total_agents":4,"catalog_rows":3,"drift":1}' ]
  run bash "$S" --check
  [[ "$output" == *"drift detected"* ]]
  [[ "$output" == *"Fix: bash"* ]]
  bash "$S" --apply >/dev/null
  run bash "$S" --check
  [ "$status" -eq 0 ]
  mv "$T/agents/nuevo.md" "$T/agents/alpha.md" "$T/apartado/"
  run bash "$S" --check --json
  [ "$status" -eq 1 ]
  [ "$output" = '{"verdict":"FAIL","total_agents":2,"catalog_rows":4,"drift":1}' ]
}

@test "sync aislado: --apply conserva el frontmatter YAML previo del catalogo" {
  mk_agents_tree
  printf -- '---\ncontext_tier: T2\ntoken_budget: 900\n---\n\nviejo\n' > "$CAT"
  run bash "$S" --apply
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$CAT")" = "---" ]
  [ "$(sed -n 2p "$CAT")" = "context_tier: T2" ]
  [ "$(sed -n 3p "$CAT")" = "token_budget: 900" ]
  [ "$(sed -n 4p "$CAT")" = "---" ]
  run grep -q viejo "$CAT"
  [ "$status" -ne 0 ]
  grep -q "^# Agents Catalog" "$CAT"
}

@test "sync aislado: --apply --json informa accion y total; un catalogo sin frontmatter no gana uno" {
  mk_agents_tree
  run bash "$S" --apply --json
  [ "$output" = "{\"action\":\"applied\",\"path\":\"$CAT\",\"total_agents\":3}" ]
  [ "$(sed -n 1p "$CAT")" = "# Agents Catalog (auto-generated by scripts/agents-catalog-sync.sh)" ]
}

@test "sync aislado: errores de uso salen con 2" {
  mk_agents_tree
  run bash "$S"
  [ "$status" -eq 2 ]
  [[ "$output" == *"required"* ]]
  run bash "$S" --bogus
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown arg '--bogus'"* ]]
  AGENTS_DIR="$T/nada" run bash "$S" --generate
  [ "$status" -eq 2 ]
  [[ "$output" == *"agents dir not found"* ]]
  run bash "$S" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--apply"* ]]
}

@test "sync aislado: descripcion larga se trunca a 120 caracteres" {
  mk_agents_tree
  long=$(printf 'x%.0s' $(seq 1 300))
  printf -- '---\nname: largo\ndescription: %s\n---\n' "$long" > "$T/agents/largo.md"
  run bash "$S" --generate
  row=$(printf '%s\n' "$output" | grep '^| largo ')
  desc=${row#| largo | (default) | }
  desc=${desc%|}
  desc=${desc%% }
  [ "${#desc}" -eq 120 ]
}
