#!/usr/bin/env bats
# Ref: docs/specs/SE-404-proportional-process-gates.spec.md (AC1-AC6)
# Repo git temporal por test; nunca toca el repo real.

setup() {
  ROOT_DIR_REAL="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  GATES="$ROOT_DIR_REAL/scripts/pr-plan-gates.sh"
  export TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d)}"
  REPO="$TMPDIR/repo"; mkdir -p "$REPO"; cd "$REPO"
  git init -q -b main
  git config user.email t@t; git config user.name t
  mkdir -p docs/specs docs/propuestas docs/rules/domain scripts tests CHANGELOG.d output
  printf '#!/usr/bin/env bash\necho bad\n' > scripts/val.sh
  echo "# repo" > README.md
  git add -A; git commit -qm init
  git update-ref refs/remotes/origin/main HEAD
  export ROOT="$REPO" BRANCH="agent/test"
  export G13_FIX_TRACE_TIMEOUT=60
}

teardown() { cd /; }

summary() { # $1 = extra lines
  printf '## Qué hace este PR (en lenguaje no técnico)\n\nTexto.\n\n%s\n' "$1" > "$REPO/.pr-summary.md"
}

run_g13() {
  git checkout -q -B "$BRANCH"
  git add -A
  git commit -qm "${1:-agent: cambio}" >/dev/null
  source "$GATES"
  g13_scope_trace
}

# ── G13 v2: localización de specs y formatos de AC ──────────────────────────

@test "AC1: spec in docs/specs is found (no 'file not found' WARN)" {
  printf -- '---\nstatus: APPROVED\n---\n# SE-500\n\n- AC1: add a rebase planner\n' > docs/specs/SE-500-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-500"
  echo x > scripts/rebase-planner.sh
  output=$(run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "AC1: all six AC formats contribute tokens" {
  cat > docs/specs/SE-501-x.spec.md <<'S'
# SE-501
- [ ] AC-1 alpha-widget
- [x] AC-2 bravo-widget
- AC3: charlie-widget
- AC-4: delta-widget
- **AC5** echo-widget
AC6: foxtrot-widget
S
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-501"
  for n in alpha bravo charlie delta echo foxtrot; do echo x > "scripts/$n-widget.sh"; done
  output=$(run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "AC2: a file matched by a glob path in the spec passes" {
  printf '# SE-502\n- AC1: frontmatter en `docs/rules/domain/*.md`\n' > docs/specs/SE-502-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-502"
  echo x > docs/rules/domain/zeta-rule.md
  output=$(run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "self-spec: touching the referenced spec in docs/specs is in scope" {
  printf '# SE-503\n- AC1: nothing\n' > docs/specs/SE-503-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-503"
  printf '# SE-503\n- AC1: nothing else\n' > docs/specs/SE-503-x.spec.md
  output=$(run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "reject: an orphan file still FAILs with v2 formats" {
  printf '# SE-504\n- AC1: kilo-widget\n' > docs/specs/SE-504-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-504"
  echo x > scripts/unrelated-thing.sh
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"unrelated-thing.sh"* ]]
}

@test "AC2+: a backticked dotfile named in the spec traces without override" {
  printf '# SE-505\n- AC1: ignorar artefactos en `.gitignore`\n' > docs/specs/SE-505-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-505"
  echo "out/" > .gitignore
  output=$(run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "AC2+: a backticked extensionless path is matched exactly" {
  printf '# SE-506\n- AC1: revisores\n\nEntregables: `.github/CODEOWNERS`\n' > docs/specs/SE-506-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-506"
  mkdir -p .github; echo x > .github/CODEOWNERS
  output=$(run_g13)
  [[ "$output" == *"B8 attention-anchor present"* ]]
}

@test "reject: a sibling dotfile not named in the spec still FAILs" {
  printf '# SE-507\n- AC1: ignorar artefactos en `.gitignore`\n' > docs/specs/SE-507-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-507"
  echo x > .gitattributes
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *".gitattributes"* ]]
}

@test "reject: a directory mention does not open its whole subtree" {
  printf '# SE-508\n- AC1: trabajo en `scripts/helpers`\n' > docs/specs/SE-508-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-508"
  mkdir -p scripts/helpers; echo x > scripts/helpers/other
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"scripts/helpers/other"* ]]
}

@test "reject: a dotfile mentioned without backticks does not count" {
  printf '# SE-509\n- AC1: hablamos de .gitignore sin formato\n' > docs/specs/SE-509-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-509"
  echo "out/" > .gitignore
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
}

@test "AC3: every Scope-trace skip is logged to output/g13-overrides.jsonl" {
  summary "Scope-trace: skip — motivo suficientemente largo"
  echo x > scripts/any.sh
  output=$(run_g13)
  [[ "$output" == *"skipped via override"* ]]
  run jq -r '.branch + "|" + .reason' "$REPO/output/g13-overrides.jsonl"
  [[ "$output" == "agent/test|motivo suficientemente largo" ]]
}

# ── Fix-trace ───────────────────────────────────────────────────────────────

make_fix() { # test passes only when scripts/val.sh prints "good"
  cat > tests/test-val.bats <<'T'
@test "val says good" {
  [ "$(bash "$BATS_TEST_DIRNAME/../scripts/val.sh")" = "good" ]
}
T
  printf '#!/usr/bin/env bash\necho good\n' > scripts/val.sh
}

@test "AC4: Fix-trace with a test failing at base and passing at HEAD passes G13" {
  make_fix
  echo "- fix" > CHANGELOG.d/fix.md
  summary "Fix-trace: tests/test-val.bats"
  output=$(run_g13)
  [[ "$output" == *"fix traced to failing test"* ]]
  [[ "$output" != FAIL* ]]
}

@test "AC5: Fix-trace with a test that already passed at base FAILs" {
  printf '@test "trivial" { true; }\n' > tests/test-trivial.bats
  git add -A; git commit -qm t; git update-ref refs/remotes/origin/main HEAD
  printf '#!/usr/bin/env bash\necho other\n' > scripts/val.sh
  printf '@test "trivial" { true; }\n# scripts/val.sh\n' > tests/test-trivial.bats
  summary "Fix-trace: tests/test-trivial.bats"
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"did not fail at base"* ]]
}

@test "AC6: Fix-trace with a changed file outside the test chain FAILs naming it" {
  make_fix
  echo x > scripts/unrelated.sh
  summary "Fix-trace: tests/test-val.bats"
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"scripts/unrelated.sh"* ]]
}

@test "negative: Fix-trace whose test still fails at HEAD FAILs" {
  cat > tests/test-val.bats <<'T'
@test "val says good" {
  [ "$(bash "$BATS_TEST_DIRNAME/../scripts/val.sh")" = "good" ]
}
T
  summary "Fix-trace: tests/test-val.bats"
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"does not pass at HEAD"* ]]
}

@test "missing: Fix-trace naming a nonexistent test FAILs" {
  echo x > scripts/val.sh
  summary "Fix-trace: tests/no-such-test.bats"
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"no-such-test.bats"* ]]
}

@test "safety: Fix-trace never leaves a temporary worktree behind" {
  make_fix
  summary "Fix-trace: tests/test-val.bats"
  run_g13 >/dev/null
  [ "$(git -C "$REPO" worktree list | wc -l)" -eq 1 ]
}

@test "safety: pr-plan-gates.sh keeps set -uo pipefail" {
  head -5 "$GATES" | grep -q 'set -uo pipefail'
}

@test "empty: an empty Fix-trace line FAILs instead of passing vacuously" {
  echo x > scripts/val.sh
  summary "Fix-trace:"
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"no test named"* ]]
}

@test "boundary: non-bats/py test type in Fix-trace is rejected with its name" {
  echo "echo hi" > tests/check.sh
  summary "Fix-trace: tests/check.sh"
  output=$(run_g13)
  [[ "$output" == FAIL* ]]
  [[ "$output" == *"tests/check.sh"* ]]
}

@test "status: g13 returns 0 (verdict is in the output, never in the exit code)" {
  printf '# SE-505\n- AC1: lima-widget\n' > docs/specs/SE-505-x.spec.md
  git add -A; git commit -qm spec; git update-ref refs/remotes/origin/main HEAD
  summary "Scope-trace: SE-505"
  echo x > scripts/other-file.sh
  git checkout -q -B "$BRANCH"; git add -A; git commit -qm c
  source "$GATES"
  run g13_scope_trace
  [ "$status" -eq 0 ]
  [[ "$output" == FAIL* ]]
}
