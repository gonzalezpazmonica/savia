#!/usr/bin/env bats
# BATS tests for Tier 1 probes (SE-037/038/039 Slice 1).
# Consolida tests de 3 scripts porque los 3 son probes read-only con el
# mismo patrón estructural (script → output/*.md report → exit code).
#
# Ref: ROADMAP.md §Tier 1.1/1.2/1.3
# Scripts bajo test:
#   - scripts/hook-bench-all.sh (SE-037 Slice 1)
#   - scripts/agent-size-audit.sh (SE-038 Slice 1)
#   - scripts/audit-all-bats.sh (SE-039 Slice 1)
#
# Safety: los 3 scripts tienen `set -uo pipefail`. Tests leen scripts y
# ejecutan en modo --quiet para no ensuciar stdout.

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
}

teardown() {
  cd /
}

# ── Structure / existence ──────────────────────────────────────────────────

@test "hook-bench-all script exists and is executable" {
  [[ -x "scripts/hook-bench-all.sh" ]]
}

@test "agent-size-audit script exists and is executable" {
  [[ -x "scripts/agent-size-audit.sh" ]]
}

@test "audit-all-bats script exists and is executable" {
  [[ -x "scripts/audit-all-bats.sh" ]]
}

# ── Safety header (all 3) ──────────────────────────────────────────────────

@test "hook-bench-all uses set -uo pipefail" {
  run grep -cE '^set -[ueuo]+ pipefail' "scripts/hook-bench-all.sh"
  [[ "$output" -ge 1 ]]
}

@test "agent-size-audit uses set -uo pipefail" {
  run grep -cE '^set -[ueuo]+ pipefail' "scripts/agent-size-audit.sh"
  [[ "$output" -ge 1 ]]
}

@test "audit-all-bats uses set -uo pipefail" {
  run grep -cE '^set -[ueuo]+ pipefail' "scripts/audit-all-bats.sh"
  [[ "$output" -ge 1 ]]
}

# ── bash -n syntax check ───────────────────────────────────────────────────

@test "hook-bench-all passes bash -n" {
  run bash -n "scripts/hook-bench-all.sh"
  [ "$status" -eq 0 ]
}

@test "agent-size-audit passes bash -n" {
  run bash -n "scripts/agent-size-audit.sh"
  [ "$status" -eq 0 ]
}

@test "audit-all-bats passes bash -n" {
  run bash -n "scripts/audit-all-bats.sh"
  [ "$status" -eq 0 ]
}

# ── CLI surface ────────────────────────────────────────────────────────────

@test "hook-bench-all --help exits 0" {
  run bash scripts/hook-bench-all.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"runs"* ]]
}

@test "agent-size-audit --help exits 0" {
  run bash scripts/agent-size-audit.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rule"* ]] || [[ "$output" == *"exception"* ]]
}

@test "audit-all-bats --help exits 0" {
  run bash scripts/audit-all-bats.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"min-score"* ]]
}

@test "hook-bench-all rejects unknown arg" {
  run bash scripts/hook-bench-all.sh --bogus
  [ "$status" -ne 0 ]
}

@test "agent-size-audit rejects unknown arg" {
  run bash scripts/agent-size-audit.sh --bogus
  [ "$status" -ne 0 ]
}

@test "audit-all-bats rejects unknown arg" {
  run bash scripts/audit-all-bats.sh --bogus
  [ "$status" -ne 0 ]
}

# ── Report generation ──────────────────────────────────────────────────────

@test "hook-bench-all writes a markdown report" {
  local out_before out_after
  out_before=$(find output -name 'hook-bench-report-*.md' 2>/dev/null | wc -l)
  bash scripts/hook-bench-all.sh --runs 1 --quiet >/dev/null 2>&1 || true
  out_after=$(find output -name 'hook-bench-report-*.md' 2>/dev/null | wc -l)
  [[ "$out_after" -ge 1 ]]
}

@test "agent-size-audit writes a markdown report" {
  bash scripts/agent-size-audit.sh --quiet >/dev/null 2>&1 || true
  local count
  count=$(find output -name 'agent-size-report-*.md' 2>/dev/null | wc -l)
  [[ "$count" -ge 1 ]]
}

@test "audit-all-bats writes a markdown report" {
  bash scripts/audit-all-bats.sh --quiet >/dev/null 2>&1 || true
  local count
  count=$(find output -name 'bats-audit-sweep-*.md' 2>/dev/null | wc -l)
  [[ "$count" -ge 1 ]]
}

@test "hook-bench-all report is non-empty" {
  bash scripts/hook-bench-all.sh --runs 1 --quiet >/dev/null 2>&1 || true
  local latest
  latest=$(ls -t output/hook-bench-report-*.md 2>/dev/null | head -1)
  [[ -s "$latest" ]]
}

@test "hook-bench-all report contains SLA table" {
  bash scripts/hook-bench-all.sh --runs 1 --quiet >/dev/null 2>&1 || true
  local latest
  latest=$(ls -t output/hook-bench-report-*.md 2>/dev/null | head -1)
  run grep -c "SLA critical\|SLA analysis" "$latest"
  [[ "$output" -ge 1 ]]
}

@test "agent-size-audit report lists Rule #22 SLA" {
  bash scripts/agent-size-audit.sh --quiet >/dev/null 2>&1 || true
  local latest
  latest=$(ls -t output/agent-size-report-*.md 2>/dev/null | head -1)
  run grep -c "4096\|Rule #22" "$latest"
  [[ "$output" -ge 1 ]]
}

@test "audit-all-bats report contains Bottom decile section" {
  bash scripts/audit-all-bats.sh --quiet >/dev/null 2>&1 || true
  local latest
  latest=$(ls -t output/bats-audit-sweep-*.md 2>/dev/null | head -1)
  run grep -c "Bottom decile\|bottom decile" "$latest"
  [[ "$output" -ge 1 ]]
}

# ── Read-only invariant (probes must NOT modify repo state) ────────────────

@test "hook-bench-all does NOT modify any tracked repo files" {
  local before_hash after_hash
  before_hash=$(find .claude/hooks scripts docs tests -type f \( -name '*.sh' -o -name '*.md' -o -name '*.bats' \) -exec md5sum {} \; 2>/dev/null | sort | md5sum | awk '{print $1}')
  bash scripts/hook-bench-all.sh --runs 1 --quiet >/dev/null 2>&1 || true
  after_hash=$(find .claude/hooks scripts docs tests -type f \( -name '*.sh' -o -name '*.md' -o -name '*.bats' \) -exec md5sum {} \; 2>/dev/null | sort | md5sum | awk '{print $1}')
  [[ "$before_hash" == "$after_hash" ]]
}

@test "agent-size-audit does NOT modify .opencode/agents/" {
  local before_hash after_hash
  before_hash=$(find .claude/agents -type f -name '*.md' -exec md5sum {} \; 2>/dev/null | sort | md5sum | awk '{print $1}')
  bash scripts/agent-size-audit.sh --quiet >/dev/null 2>&1 || true
  after_hash=$(find .claude/agents -type f -name '*.md' -exec md5sum {} \; 2>/dev/null | sort | md5sum | awk '{print $1}')
  [[ "$before_hash" == "$after_hash" ]]
}

@test "audit-all-bats does NOT modify tests/" {
  local before_hash after_hash
  before_hash=$(find tests -type f -name '*.bats' -exec md5sum {} \; 2>/dev/null | sort | md5sum | awk '{print $1}')
  bash scripts/audit-all-bats.sh --quiet >/dev/null 2>&1 || true
  after_hash=$(find tests -type f -name '*.bats' -exec md5sum {} \; 2>/dev/null | sort | md5sum | awk '{print $1}')
  [[ "$before_hash" == "$after_hash" ]]
}

# ── Bounded concurrency (audit-all-bats) ──────────────────────────────────

@test "audit-all-bats respects MAX_PARALLEL bound" {
  run grep -cE 'MAX_PARALLEL' "scripts/audit-all-bats.sh"
  [[ "$output" -ge 1 ]]
}

@test "audit-all-bats uses jobs -rp + wait -n pattern (bounded concurrency)" {
  run grep -cE 'jobs -rp|wait -n' "scripts/audit-all-bats.sh"
  [[ "$output" -ge 2 ]]
}

# ── Exit codes ─────────────────────────────────────────────────────────────

@test "agent-size-audit exits 0 when no violations (sandbox)" {
  local sandbox="$BATS_TEST_TMPDIR/.claude/agents"
  mkdir -p "$sandbox"
  echo "small" > "$sandbox/tiny.md"
  run env REPO_ROOT="$BATS_TEST_TMPDIR" bash scripts/agent-size-audit.sh --quiet
  [ "$status" -eq 0 ]
}

@test "agent-size-audit exits 1 when violation without exception (sandbox)" {
  local sandbox="$BATS_TEST_TMPDIR/.claude/agents"
  mkdir -p "$sandbox"
  # Create a 5KB file with no frontmatter exception
  head -c 5000 /dev/urandom | base64 > "$sandbox/huge.md"
  run env REPO_ROOT="$BATS_TEST_TMPDIR" bash scripts/agent-size-audit.sh --quiet
  [ "$status" -eq 1 ]
}

@test "agent-size-audit respects size_exception frontmatter (sandbox)" {
  local sandbox="$BATS_TEST_TMPDIR/.claude/agents"
  mkdir -p "$sandbox"
  {
    echo "---"
    echo "name: huge"
    echo "size_exception: complex orchestrator, split not viable"
    echo "---"
    head -c 5000 /dev/urandom | base64
  } > "$sandbox/huge.md"
  run env REPO_ROOT="$BATS_TEST_TMPDIR" bash scripts/agent-size-audit.sh --quiet
  [ "$status" -eq 0 ]
}

# ── Negative cases ─────────────────────────────────────────────────────────

@test "negative: hook-bench-all rejects runs > 20" {
  run bash scripts/hook-bench-all.sh --runs 100
  [ "$status" -ne 0 ]
}

@test "negative: hook-bench-all rejects runs = 0" {
  run bash scripts/hook-bench-all.sh --runs 0
  [ "$status" -ne 0 ]
}

@test "negative: audit-all-bats exits early if auditor missing" {
  # Simulate missing auditor by pointing at nonexistent dir
  local fake_repo="$BATS_TEST_TMPDIR/fake-repo"
  mkdir -p "$fake_repo/tests" "$fake_repo/scripts"
  run env REPO_ROOT="$fake_repo" bash scripts/audit-all-bats.sh --quiet
  [ "$status" -eq 2 ]
}

@test "negative: empty hooks dir fails explicitly" {
  local fake="$BATS_TEST_TMPDIR/empty-hooks"
  mkdir -p "$fake/.opencode/hooks"
  run env REPO_ROOT="$fake" bash scripts/hook-bench-all.sh --runs 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"ERROR: no hook scripts found"* ]]
}

@test "hook-bench-all follows an in-repo hooks symlink" {
  local fake="$BATS_TEST_TMPDIR/symlink-hooks"
  mkdir -p "$fake/.claude/hooks" "$fake/.opencode"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/.claude/hooks/one.sh"
  chmod +x "$fake/.claude/hooks/one.sh"
  ln -s ../.claude/hooks "$fake/.opencode/hooks"

  run env REPO_ROOT="$fake" bash scripts/hook-bench-all.sh --runs 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"total=1"* ]]
}

@test "hook-bench-all requires both critical convention and hot-path registration" {
  local fake="$BATS_TEST_TMPDIR/registered-hooks"
  mkdir -p "$fake/.claude/hooks" "$fake/.opencode"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/.claude/hooks/post-registered.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/.claude/hooks/pre-unregistered.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/.claude/hooks/neutral-registered.sh"
  chmod +x "$fake/.claude/hooks/"*.sh
  ln -s ../.claude/hooks "$fake/.opencode/hooks"
  cat > "$fake/.claude/settings.json" <<'JSON'
{"hooks":{"PreToolUse":[{"hooks":[
  {"command":"$CLAUDE_PROJECT_DIR/.opencode/hooks/post-registered.sh"},
  {"command":"$CLAUDE_PROJECT_DIR/.opencode/hooks/neutral-registered.sh"}
]}]}}
JSON

  run env REPO_ROOT="$fake" bash scripts/hook-bench-all.sh --runs 1

  [ "$status" -eq 0 ]
  grep -q '| `post-registered` | critical |' "$fake/output/hook-bench-report-"*.md
  grep -q '| `pre-unregistered` | analysis |' "$fake/output/hook-bench-report-"*.md
  grep -q '| `neutral-registered` | analysis |' "$fake/output/hook-bench-report-"*.md
}

@test "negative: empty agents dir produces report with 0 agents" {
  local fake="$BATS_TEST_TMPDIR/empty-agents"
  mkdir -p "$fake/.claude/agents"
  run env REPO_ROOT="$fake" bash scripts/agent-size-audit.sh --quiet
  [ "$status" -eq 0 ]
}

# ── Edge cases ─────────────────────────────────────────────────────────────

@test "edge: hook-bench-all default runs is 5" {
  run grep -E 'RUNS=.*5' "scripts/hook-bench-all.sh"
  [ "$status" -eq 0 ]
}

@test "edge: agent-size-audit SLA is exactly 4096 bytes (Rule #22)" {
  run grep -E 'SLA_BYTES=4096' "scripts/agent-size-audit.sh"
  [ "$status" -eq 0 ]
}

@test "edge: audit-all-bats default min-score is 80 (SPEC-055)" {
  run grep -E 'MIN_SCORE=80' "scripts/audit-all-bats.sh"
  [ "$status" -eq 0 ]
}

@test "edge: all 3 scripts reference ROADMAP Tier 1 (traceability)" {
  run grep -l 'ROADMAP\|Tier 1' scripts/hook-bench-all.sh scripts/agent-size-audit.sh scripts/audit-all-bats.sh
  local count
  count=$(echo "$output" | wc -l)
  [[ "$count" -ge 3 ]]
}

@test "edge: all 3 scripts write reports to output/ directory" {
  for s in scripts/hook-bench-all.sh scripts/agent-size-audit.sh scripts/audit-all-bats.sh; do
    run grep -c 'OUTPUT_DIR.*output' "$s"
    [[ "$output" -ge 1 ]]
  done
}

@test "edge: all 3 scripts support --quiet flag" {
  for s in scripts/hook-bench-all.sh scripts/agent-size-audit.sh scripts/audit-all-bats.sh; do
    run grep -c '\-\-quiet' "$s"
    [[ "$output" -ge 1 ]]
  done
}

@test "edge: report format includes Interpretation section (actionable)" {
  for report_glob in 'hook-bench-report-*.md' 'agent-size-report-*.md' 'bats-audit-sweep-*.md'; do
    local latest
    latest=$(ls -t output/$report_glob 2>/dev/null | head -1)
    if [[ -f "$latest" ]]; then
      run grep -c "Interpretation\|interpretation" "$latest"
      [[ "$output" -ge 1 ]]
    fi
  done
}
