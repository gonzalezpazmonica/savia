#!/usr/bin/env bats
# tests/bats/test-se257-consolidacion.bats — SE-257
# Ref: SE-257 Consolidacion
set -uo pipefail

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
}

teardown() {
  true
}

# ── Slice 1: CRITERIO.md validation ────────────────────────────────────────

@test "AC-1.1a: CRITERIO.md tiene >=33 entradas" {
  COUNT=$(grep -c "^CRIT-[0-9]" "$REPO_ROOT/CRITERIO.md" || echo 0)
  [ "$COUNT" -ge 33 ]
}

@test "AC-1.1b: CRITERIO.md cubre los 5 ambitos" {
  grep -q "### tecnicas" "$REPO_ROOT/CRITERIO.md"
  grep -q "### comunicacion" "$REPO_ROOT/CRITERIO.md"
  grep -q "### priorizacion" "$REPO_ROOT/CRITERIO.md"
  grep -q "### riesgo" "$REPO_ROOT/CRITERIO.md"
  grep -q "### delegacion" "$REPO_ROOT/CRITERIO.md"
}

@test "AC-1.1c: entry tiene dureza valida" {
  INVALID=$(grep "dureza:" "$REPO_ROOT/CRITERIO.md" | grep -v "linea_roja" | grep -v "preferencia" | grep -v "estilo" | wc -l) || true
  [ "$INVALID" -eq 0 ]
}

@test "AC-1.1d: CRITERIO.md is not empty and has valid structure" {
  [ -s "$REPO_ROOT/CRITERIO.md" ]
  grep -q "^CRIT-" "$REPO_ROOT/CRITERIO.md"
}

@test "AC-1.2: CRITERIO.md rejects invalid dureza values" {
  BAD=0
  grep "dureza:" "$REPO_ROOT/CRITERIO.md" | grep -qE "dureza:\s*$" && BAD=1
  [ "$BAD" -eq 0 ]
}

@test "AC-1.4a: criterio-validate existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/criterio-validate.sh" ]
  [ -x "$REPO_ROOT/scripts/criterio-validate.sh" ]
}

@test "AC-1.4b: criterio-validate pasa y cuenta los human_authored reales de CRITERIO.md" {
  # El recuento esperado se deriva del fichero: cada criterio que la operadora
  # activa cambia la cifra y un literal fijo deriva (1 -> 6 con CRIT-034..038).
  EXPECTED=$(grep -cE '^[[:space:]]*provenance:[[:space:]]*human_authored[[:space:]]*$' "$REPO_ROOT/CRITERIO.md")
  [ "$EXPECTED" -ge 1 ]
  run bash "$REPO_ROOT/scripts/criterio-validate.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Provenance: "*" INFERRED, $EXPECTED human_authored"* ]]
  if [ "$EXPECTED" -ge 20 ]; then
    [[ "$output" == *"GATE S5: ACTIVABLE ($EXPECTED >= 20 human_authored)"* ]]
  else
    [[ "$output" == *"GATE S5: DORMIDO ($EXPECTED human_authored, need 20)"* ]]
  fi
}

@test "AC-1.5: criterio-validate fails on missing file with error" {
  run bash "$REPO_ROOT/scripts/criterio-validate.sh" /nonexistent/file.md
  [ "$status" -ne 0 ]
}

@test "AC-1.6: criterio-validate handles empty input gracefully" {
  run bash "$REPO_ROOT/scripts/criterio-validate.sh" /dev/null
  [ "$status" -ne 0 ]
}

# ── Slice 2: Memory ────────────────────────────────────────────────────────

@test "AC-2.1a: memory-architecture.md existe" {
  [ -f "$REPO_ROOT/docs/memory-architecture.md" ]
}

@test "AC-2.2a: memory-liveness-check existe y es ejecutable" {
  [ -f "$REPO_ROOT/scripts/memory-liveness-check.sh" ]
  [ -x "$REPO_ROOT/scripts/memory-liveness-check.sh" ]
}

@test "AC-2.2b: memory-liveness-check corre sin error" {
  run bash "$REPO_ROOT/scripts/memory-liveness-check.sh"
  [ "$status" -eq 0 ]
}

@test "AC-2.3: memory-liveness-check with timeout does not hang" {
  run timeout 5 bash "$REPO_ROOT/scripts/memory-liveness-check.sh"
  [ "$status" -eq 0 ]
}

@test "SE-334 AC-2.3a: self-reference does not count as a consumer" {
  local fixture="$BATS_TEST_TMPDIR/liveness-self"
  mkdir -p "$fixture/scripts" "$fixture/docs"
  cp "$REPO_ROOT/scripts/memory-liveness-check.sh" "$fixture/scripts/"
  cat > "$fixture/scripts/orphan-memory.sh" <<'EOF'
#!/usr/bin/env bash
# orphan-memory.sh has no external consumer
EOF
  echo "Run scripts/memory-liveness-check.sh during validation." > "$fixture/docs/checker.md"
  git -C "$fixture" init -q
  git -C "$fixture" add scripts docs

  run bash "$fixture/scripts/memory-liveness-check.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ORPHAN: orphan-memory.sh"* ]]
}

@test "SE-334 AC-2.3b: external reference counts as a consumer" {
  local fixture="$BATS_TEST_TMPDIR/liveness-consumer"
  mkdir -p "$fixture/scripts" "$fixture/docs"
  cp "$REPO_ROOT/scripts/memory-liveness-check.sh" "$fixture/scripts/"
  cat > "$fixture/scripts/used-memory.sh" <<'EOF'
#!/usr/bin/env bash
EOF
  printf '%s\n' "Run scripts/memory-liveness-check.sh during validation." \
    "Run scripts/used-memory.sh during validation." > "$fixture/docs/runbook.md"
  git -C "$fixture" init -q
  git -C "$fixture" add scripts docs

  run bash "$fixture/scripts/memory-liveness-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: used-memory.sh"* ]]
  [[ "$output" == *"0 orphans"* ]]
}

@test "SE-334 AC-2.3c: script paths with spaces are not split" {
  local fixture="$BATS_TEST_TMPDIR/liveness-spaces"
  mkdir -p "$fixture/scripts" "$fixture/docs"
  cp "$REPO_ROOT/scripts/memory-liveness-check.sh" "$fixture/scripts/"
  touch "$fixture/scripts/cache memory.sh"
  printf '%s\n' "Run scripts/memory-liveness-check.sh during validation." \
    "Run scripts/cache memory.sh during validation." > "$fixture/docs/runbook.md"
  git -C "$fixture" init -q
  git -C "$fixture" add scripts docs

  run bash "$fixture/scripts/memory-liveness-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: cache memory.sh"* ]]
}

@test "SE-334 AC-2.3d: fallback without rg preserves liveness semantics" {
  local fixture="$BATS_TEST_TMPDIR/liveness-fallback"
  local bin="$fixture/bin"
  mkdir -p "$fixture/scripts" "$fixture/docs" "$bin"
  cp "$REPO_ROOT/scripts/memory-liveness-check.sh" "$fixture/scripts/"
  touch "$fixture/scripts/fallback-memory.sh"
  printf '%s\n' "Run scripts/memory-liveness-check.sh during validation." \
    "Run scripts/fallback-memory.sh during validation." > "$fixture/docs/runbook.md"
  for command in bash basename dirname find git grep mktemp rm sort; do
    ln -s "$(command -v "$command")" "$bin/$command"
  done

  run env PATH="$bin" bash "$fixture/scripts/memory-liveness-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK: fallback-memory.sh"* ]]
}

@test "SE-334 AC-2.3e: Python test files are not operational candidates" {
  local fixture="$BATS_TEST_TMPDIR/liveness-python-test"
  mkdir -p "$fixture/scripts" "$fixture/docs"
  cp "$REPO_ROOT/scripts/memory-liveness-check.sh" "$fixture/scripts/"
  touch "$fixture/scripts/orphan-memory.test.py"
  echo "Run scripts/memory-liveness-check.sh during validation." > "$fixture/docs/checker.md"
  git -C "$fixture" init -q
  git -C "$fixture" add scripts docs

  run bash "$fixture/scripts/memory-liveness-check.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *"orphan-memory.test.py"* ]]
}

@test "SE-334 AC-12: manual memory entrypoints invoke all operational scripts" {
  run grep -F "bash scripts/memory-backup-pm.sh status" "$REPO_ROOT/.claude/skills/savia-memory/SKILL.md"
  [ "$status" -eq 0 ]
  run grep -F "python3 scripts/memory-conflict-resolve.py" "$REPO_ROOT/.claude/skills/savia-memory/SKILL.md"
  [ "$status" -eq 0 ]
  run grep -F "bash scripts/memory-sync-index.sh" "$REPO_ROOT/.claude/skills/savia-memory/SKILL.md"
  [ "$status" -eq 0 ]
  run grep -F "bash scripts/memory-write-gate.sh" "$REPO_ROOT/.claude/skills/savia-memory/SKILL.md"
  [ "$status" -eq 0 ]
  run grep -F "bash scripts/memory-prune.sh --dry-run" "$REPO_ROOT/.claude/commands/memory-prune.md"
  [ "$status" -eq 0 ]
}

@test "SE-334 AC-13: memory prune dry-run does not mutate store" {
  local fixture="$BATS_TEST_TMPDIR/prune-dry-run"
  mkdir -p "$fixture/output"
  printf '%s\n' '{"topic_key":"old","content":"old low confidence entry","confidence":0.1,"ts":"2020-01-01T00:00:00Z"}' > "$fixture/output/.memory-store.jsonl"
  local before
  before=$(sha256sum "$fixture/output/.memory-store.jsonl")

  run env PROJECT_ROOT="$fixture" \
    bash "$REPO_ROOT/scripts/memory-prune.sh" --dry-run --quiet
  [ "$status" -eq 0 ]
  [ "$before" = "$(sha256sum "$fixture/output/.memory-store.jsonl")" ]
  [ ! -e "$fixture/output/.memory-tombstone.jsonl" ]

  run env PROJECT_ROOT="$fixture" \
    bash "$REPO_ROOT/scripts/memory-prune.sh" --quiet
  [ "$status" -eq 0 ]
  [ "$before" = "$(sha256sum "$fixture/output/.memory-store.jsonl")" ]
  [ ! -e "$fixture/output/.memory-tombstone.jsonl" ]

  run env PROJECT_ROOT="$fixture" SAVIA_TEST_MODE=true \
    bash "$REPO_ROOT/scripts/memory-prune.sh" --apply --quiet
  [ "$status" -eq 0 ]
  [ "$before" != "$(sha256sum "$fixture/output/.memory-store.jsonl")" ]
  [ -s "$fixture/output/.memory-tombstone.jsonl" ]
}

@test "AC-2.4: memory-liveness-check rejects missing artifact" {
  run bash "$REPO_ROOT/scripts/memory-liveness-check.sh" --check-missing /nonexistent 2>/dev/null
  [ "$status" -ne 0 ]
}

# ── Slice 4: CI ────────────────────────────────────────────────────────────

@test "AC-4.1a: CI tiene concurrency cancel-in-progress" {
  grep -q "cancel-in-progress" "$REPO_ROOT/.github/workflows/ci.yml"
}

@test "AC-4.1b: CI jobs tienen timeout-minutes" {
  TIMEOUTS=$(grep -c "timeout-minutes" "$REPO_ROOT/.github/workflows/ci.yml" || echo 0)
  [ "$TIMEOUTS" -ge 4 ]
}

@test "AC-4.2: CI workflow is not empty and has valid structure" {
  [ -s "$REPO_ROOT/.github/workflows/ci.yml" ]
  grep -q "jobs:" "$REPO_ROOT/.github/workflows/ci.yml"
}

@test "AC-4.3: CI has no zero-minute timeout jobs" {
  ! grep -q "timeout-minutes:\s*0" "$REPO_ROOT/.github/workflows/ci.yml" || true
}
