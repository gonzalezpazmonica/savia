#!/usr/bin/env bats
# Ref: SE-079 — pr-plan G13 scope-trace gate
# Pattern: Genesis B8 ATTENTION ANCHOR + B9 GOAL STEWARD (SE-080)

setup() {
  ROOT_DIR_REAL="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$ROOT_DIR_REAL/scripts/pr-plan-gates.sh"
  GATES="$SCRIPT"

  # Isolated git repo per test — emulate the pr-plan environment
  REPO=$(mktemp -d)
  cd "$REPO"
  git init -q -b main
  git config user.email "test@savia.local"
  git config user.name "Savia Test"
  mkdir -p docs/propuestas scripts tests/structure CHANGELOG.d .scm
  echo "# repo" > README.md
  git add README.md
  git commit -q -m "init"
  # Set up an "origin/main" pointer that g13 looks for
  git update-ref refs/remotes/origin/main HEAD

  export ROOT="$REPO"
  export BRANCH="agent/test-branch"
}

teardown() {
  cd /
  rm -rf "$REPO"
}

# Helper: write a spec file with given ACs (AC tokens come from the description)
make_spec() {
  local id="$1"; shift
  cat > "$REPO/docs/propuestas/${id}-test.md" <<SPEC
---
id: ${id}
title: ${id} — test spec
status: APPROVED
effort: S 2h
---

# ${id}

## Acceptance criteria

$(for ac in "$@"; do echo "- [ ] $ac"; done)
SPEC
}

# Helper: write a .pr-summary.md with the right heading + size + spec ref
make_pr_summary() {
  local spec="$1" extra="${2:-}"
  cat > "$REPO/.pr-summary.md" <<EOF
## Qué hace este PR (en lenguaje no técnico)

This PR implements ${spec}. The goal is to add a small piece of functionality
that traces directly back to the acceptance criteria of that specification,
without dragging unrelated changes along for the ride. This long paragraph
exists only to clear the 300-character minimum required by the G11 gate.

${extra}
EOF
}

# Helper: stage + commit on branch, then call g13
branch_commit_and_run_g13() {
  git checkout -q -B "$BRANCH"
  git add -A
  git commit -q -m "${1:-feat: test commit}" >/dev/null
  source "$GATES"
  g13_scope_trace
}

# ── Usage / safe-skip cases ─────────────────────────────────────────────────

@test "g13: skipped when no changes between main and HEAD" {
  source "$GATES"
  run g13_scope_trace
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (no changes)"* ]]
}

@test "g13: WARNs when origin/main is unreachable" {
  git update-ref -d refs/remotes/origin/main
  source "$GATES"
  run g13_scope_trace
  [ "$status" -eq 0 ]
  [[ "$output" == *"origin/main unreachable"* ]]
}

@test "g13: WARN when no spec ref is detectable anywhere" {
  echo "x" > scripts/random.sh
  output=$(branch_commit_and_run_g13 "feat: random script")
  [[ "$output" == *"no spec ref"* ]]
  [[ "$output" == *"WARN"* ]]
}

@test "g13: WARN when spec id referenced but file not in docs/propuestas" {
  make_pr_summary "SE-999"
  echo "x" > scripts/random.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"SE-999"* ]]
  [[ "$output" == *"WARN"* ]]
}

# ── Happy paths ─────────────────────────────────────────────────────────────

@test "g13: PASS with B8 marker when every changed file traces to an AC token" {
  make_spec "SE-100" "AC-01 add a queue manager script with rebase logic"
  make_pr_summary "SE-100"
  echo "echo hi" > scripts/queue-manager.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
  [[ "$output" == *"SE-100"* ]]
}

@test "g13: PASS via path hint match when AC mentions an explicit path" {
  make_spec "SE-101" "AC-01 add tests/structure/test-fixture.bats with 5 cases"
  make_pr_summary "SE-101"
  echo "ok 1" > tests/structure/test-fixture.bats
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "g13: PASS — CHANGELOG.d/ fragments are always whitelisted" {
  make_spec "SE-102" "AC-01 documented intent"
  make_pr_summary "SE-102"
  echo "## frag" > CHANGELOG.d/agent-batchN-test.md
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "g13: PASS — .scm/ regen and .confidentiality-signature whitelisted" {
  make_spec "SE-103" "AC-01 documented intent"
  make_pr_summary "SE-103"
  echo "x" > .scm/INDEX.scm
  echo "y" > .confidentiality-signature
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "g13: PASS — the spec file itself counts as in-scope" {
  make_spec "SE-104" "AC-01 update the spec frontmatter"
  make_pr_summary "SE-104"
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "g13: PASS — spec id detected from commit message when summary lacks it" {
  make_spec "SE-105" "AC-01 add foobar widget"
  cat > "$REPO/.pr-summary.md" <<EOF
## Qué hace este PR (en lenguaje no técnico)

A short note. This text is just for G11 length compliance and contains no
explicit spec reference at all. The ID should be picked up from the commit
message, exercising the second-tier detection path of the G13 gate logic.
EOF
  echo "x" > scripts/foobar.sh
  output=$(branch_commit_and_run_g13 "feat: SE-105 add foobar")
  [[ "$output" == *"SE-105"* ]]
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

# ── Failure paths ───────────────────────────────────────────────────────────

@test "g13: FAIL when a changed file matches no AC and no whitelist" {
  make_spec "SE-110" "AC-01 add the queue manager script"
  make_pr_summary "SE-110"
  echo "x" > scripts/queue-manager.sh   # in scope
  echo "x" > scripts/totally-unrelated-feature.sh  # NOT in scope
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"NO MATCH"* ]]
  [[ "$output" == *"totally-unrelated-feature.sh"* ]]
}

@test "g13: FAIL message names the spec id and offers the override path" {
  make_spec "SE-111" "AC-01 widget code"
  make_pr_summary "SE-111"
  echo "x" > scripts/whatever.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"SE-111"* ]]
  [[ "$output" == *"Scope-trace: skip"* ]]
  [[ "$output" == *".pr-summary.md"* ]]
}

@test "g13: FAIL truncates list at 10 with ellipsis when many files mismatch" {
  make_spec "SE-112" "AC-01 only one in-scope file"
  make_pr_summary "SE-112"
  for i in $(seq 1 15); do echo "x" > "scripts/random${i}.sh"; done
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"more"* ]]   # ellipsis line
}

# ── Override path ───────────────────────────────────────────────────────────

@test "g13: skip override accepted with a reason ≥10 chars" {
  make_spec "SE-120" "AC-01 unrelated AC"
  make_pr_summary "SE-120" "Scope-trace: skip — emergency hotfix touching infra only"
  echo "x" > scripts/infra-thing.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"skipped via override"* ]]
}

@test "g13: skip override REJECTED when the reason is too short" {
  make_spec "SE-121" "AC-01 unrelated AC"
  make_pr_summary "SE-121" "Scope-trace: skip — short"
  echo "x" > scripts/infra-thing.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"too short"* ]]
}

# ── Static / safety / spec ref ──────────────────────────────────────────────

@test "spec ref: g13 cites SE-079 in source" {
  grep -q "SE-079" "$GATES"
}

@test "spec ref: g13 cites SE-080 attention-anchor pattern" {
  grep -q "SE-080" "$GATES"
  grep -qi "attention.anchor" "$GATES"
}

@test "safety: pr-plan-gates.sh has no destructive git commands in g13" {
  # Guard: g13 must never push/merge/reset --hard
  awk '/^g13_scope_trace\(\)/,/^}/' "$GATES" \
    | grep -E 'git[[:space:]]+(push|merge|reset[[:space:]]+--hard)' \
    && return 1 || return 0
}

@test "safety: pr-plan-gates.sh has set -uo pipefail at script level" {
  # The gates file is sourced by pr-plan.sh which set -uo pipefails;
  # the gate functions assume that strictness, so this test asserts
  # the upstream contract is documented.
  grep -qE "set -uo pipefail" "$ROOT_DIR_REAL/scripts/pr-plan.sh"
}

# ── Edge cases ──────────────────────────────────────────────────────────────

@test "edge: g13 handles spec_id detected only via branch name" {
  make_spec "SE-130" "AC-01 add scoped widget"
  cat > "$REPO/.pr-summary.md" <<EOF
## Qué hace este PR (en lenguaje no técnico)

Plain prose only, no spec ref. Padding to clear the 300-char minimum so the
gate exercises the third tier of detection — branch-name parsing — which is
the last fallback before the gate emits its WARN line.
EOF
  echo "x" > scripts/widget.sh
  BRANCH="agent/se130-widget-test"
  output=$(branch_commit_and_run_g13 "feat: widget without spec ref")
  [[ "$output" == *"SE-130"* ]]
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "edge: g13 tolerates a spec with zero AC lines" {
  cat > "$REPO/docs/propuestas/SE-131-empty.md" <<SPEC
---
id: SE-131
title: empty spec
---
# SE-131
no acceptance criteria here yet
SPEC
  make_pr_summary "SE-131"
  echo "x" > scripts/random.sh
  output=$(branch_commit_and_run_g13)
  # No AC tokens AND no path hints → unmatched, expect FAIL with a clear message
  [[ "$output" == *"FAIL"* ]] || [[ "$output" == *"WARN"* ]]
}

@test "edge: g13 case-insensitive token matching across mixed-case ACs" {
  make_spec "SE-132" "AC-01 Implement Queue Manager"
  make_pr_summary "SE-132"
  echo "x" > scripts/queue.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "edge: g13 ignores tokens shorter than 4 chars" {
  # AC has only short tokens; basename also short → should NOT spuriously match
  make_spec "SE-133" "AC-01 fix bug at io"
  make_pr_summary "SE-133"
  echo "x" > scripts/different-feature.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"FAIL"* ]]
}

@test "multi-spec: g13 unions ACs across all referenced specs in the PR" {
  # A single PR may legitimately touch >1 spec (sprint batches).
  # Each changed file must trace to ANY of the referenced specs, not just one.
  make_spec "SE-140" "AC-01 add the queue manager"
  make_spec "SE-141" "AC-01 add the cleanup utility"
  cat > "$REPO/.pr-summary.md" <<EOF
## Qué hace este PR (en lenguaje no técnico)

This batch implements both SE-140 and SE-141 in a single PR. Padding text to
reach 300 chars so G11 doesn't yell at us. The G13 gate must accept a file
that traces to SE-140 OR SE-141, not require both to be referenced from
the same fragment.
EOF
  echo "x" > scripts/queue-manager.sh   # traces to SE-140
  echo "x" > scripts/cleanup-utility.sh # traces to SE-141
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
  [[ "$output" == *"SE-140"* ]]
  [[ "$output" == *"SE-141"* ]]
}

@test "multi-spec: g13 still fails an orphan file even when multiple specs are referenced" {
  make_spec "SE-142" "AC-01 add widget"
  make_spec "SE-143" "AC-01 add gadget"
  cat > "$REPO/.pr-summary.md" <<EOF
## Qué hace este PR (en lenguaje no técnico)

Multi-spec PR for SE-142 and SE-143. Padding so G11 is satisfied with the
length of the natural-language summary that lives at the top of every PR.
Just enough words to get over the three-hundred-character minimum.
EOF
  echo "x" > scripts/widget.sh        # traces to SE-142
  echo "x" > scripts/gadget.sh        # traces to SE-143
  echo "x" > scripts/totally-orphan.sh
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"totally-orphan.sh"* ]]
}

# ── SE-500 S1 (AC-7): fragmentos de planificación ──────────────────────────
# La spec menciona los globs de fragmentos: sin la regla SE-500, cualquier
# fragmento (también el de otra spec) quedaba trazado por el glob.

@test "g13 SE-500 AC-7: PASS for planning.d and LOG.d fragments of the referenced spec" {
  make_spec "SE-200" "AC-01 register with docs/propuestas/planning.d/*.json and docs/propuestas/LOG.d/*.md"
  make_pr_summary "SE-200"
  mkdir -p docs/propuestas/planning.d docs/propuestas/LOG.d
  echo '{}' > docs/propuestas/planning.d/SE-200.json
  echo '## 2026-11-03 SE-200 PROPOSED' > docs/propuestas/LOG.d/SE-200-PROPOSED.md
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
  [[ "$output" != *"FAIL"* ]]
}

@test "g13 SE-500 AC-7: FAIL for a planning.d fragment of another spec, even under a glob hint" {
  make_spec "SE-200" "AC-01 register with docs/propuestas/planning.d/*.json and docs/propuestas/LOG.d/*.md"
  make_pr_summary "SE-200"
  mkdir -p docs/propuestas/planning.d
  echo '{}' > docs/propuestas/planning.d/SE-300.json
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"docs/propuestas/planning.d/SE-300.json"* ]]
}

@test "g13 SE-500 AC-7: FAIL for a LOG.d fragment of another spec" {
  make_spec "SE-200" "AC-01 register with docs/propuestas/planning.d/*.json and docs/propuestas/LOG.d/*.md"
  make_pr_summary "SE-200"
  mkdir -p docs/propuestas/LOG.d
  echo '## 2026-11-03 SE-301 PROPOSED' > docs/propuestas/LOG.d/SE-301-PROPOSED.md
  output=$(branch_commit_and_run_g13)
  [[ "$output" == *"FAIL"* ]]
  [[ "$output" == *"docs/propuestas/LOG.d/SE-301-PROPOSED.md"* ]]
}
