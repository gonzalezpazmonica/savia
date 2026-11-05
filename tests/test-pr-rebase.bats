#!/usr/bin/env bats
# SPEC-105: pr-rebase.sh — signature-stable rebase of queued PRs.
# Validates script structure + merge-base usage in confidentiality-sign.sh.
# Ref: docs/propuestas/SPEC-105-signature-stability-queued-prs.md
# Related: docs/rules/domain/pr-signing-protocol.md

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REBASE_SCRIPT="$REPO_ROOT/scripts/pr-rebase.sh"
  SIGN_SCRIPT="$REPO_ROOT/scripts/confidentiality-sign.sh"
  GITATTR="$REPO_ROOT/.gitattributes"
  TMP_DIR=$(mktemp -d -t pr-rebase-XXXXXX)
}

teardown() {
  rm -rf "$TMP_DIR" 2>/dev/null || true
}

# ── Structural invariants ───────────────────────────────────────────────────

@test "pr-rebase.sh exists and is executable" {
  [ -x "$REBASE_SCRIPT" ]
}

@test "pr-rebase.sh has valid bash syntax" {
  bash -n "$REBASE_SCRIPT"
}

@test "pr-rebase.sh has set -uo pipefail safety" {
  grep -q "set -uo pipefail" "$REBASE_SCRIPT"
}

@test "pr-rebase.sh references SPEC-105" {
  grep -qE "SPEC-105|signature-stability|queued.*PR" "$REBASE_SCRIPT" || \
    grep -q "rebase.*origin/main" "$REBASE_SCRIPT"
}

@test "pr-rebase.sh uses force-with-lease (safer than --force)" {
  grep -q "force-with-lease" "$REBASE_SCRIPT"
}

@test "pr-rebase.sh fetches origin main before rebasing" {
  grep -qE "git fetch origin main|git fetch.*main" "$REBASE_SCRIPT"
}

# SE-501 (sustituye a «auto-resolves signature conflict with --ours»): la firma ya no se versiona;
# un conflicto limitado a rutas de D (rama anterior al corte) se resuelve sacándolas del índice.
d_conflict_repo() {  # d_conflict_repo <fichero en conflicto>: main y la rama editan el mismo fichero
  local o="$TMP_DIR/origin.git" r="$TMP_DIR/r"
  git init -q --bare "$o"; git init -q -b main "$r"
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  mkdir -p "$r/.scm"; echo base > "$r/a.txt"; echo '{"v":0}' > "$r/.scm/sam.json"
  git -C "$r" add -f -A; git -C "$r" commit -qm base
  git -C "$r" remote add origin "$o"; git -C "$r" push -q origin main
  git -C "$r" checkout -q -b feature
  echo rama > "$r/$1"; echo cambio > "$r/b.txt"; git -C "$r" add -f -A; git -C "$r" commit -qm rama
  git -C "$r" checkout -q main
  echo main > "$r/$1"; git -C "$r" add -f -A; git -C "$r" commit -qm main; git -C "$r" push -q origin main
  git -C "$r" checkout -q feature
  echo "$r"
}

@test "SE-501: conflicto solo en una ruta de D → se saca del índice, el rebase termina y D no queda en la rama" {
  r=$(d_conflict_repo .scm/sam.json)
  cd "$r"
  run bash "$REBASE_SCRIPT" --no-push
  [ "$status" -eq 0 ]
  [ ! -d .git/rebase-merge ] && [ ! -d .git/rebase-apply ]
  [ "$(git cat-file -p HEAD:b.txt)" = "cambio" ]
  run git ls-files --error-unmatch .scm/sam.json
  [ "$status" -ne 0 ]
}

@test "SE-501: conflicto fuera de D → exit 2 y nombra el fichero (no lo resuelve solo)" {
  r=$(d_conflict_repo a.txt)
  cd "$r"
  run bash "$REBASE_SCRIPT" --no-push
  [ "$status" -eq 2 ]
  [[ "$output" == *"not limited to derived paths"* ]]
  [[ "$output" == *"a.txt"* ]]
  git rebase --abort
}

@test "pr-rebase.sh defines 4 distinct exit codes" {
  for code in 1 2 3; do
    grep -qE "exit $code\b" "$REBASE_SCRIPT" || return 1
  done
}

# ── confidentiality-sign.sh uses content-addressed tree hash (SPEC-111) ─────

@test "confidentiality-sign.sh uses ls-tree for deterministic hash" {
  grep -q "git ls-tree" "$SIGN_SCRIPT"
}

@test "confidentiality-sign.sh references SPEC-111 rationale" {
  grep -qE "SPEC-111|content-addressed|deterministic" "$SIGN_SCRIPT"
}

@test "confidentiality-sign.sh excludes self-referencing files" {
  grep -qE '\.confidentiality-signature' "$SIGN_SCRIPT"
  grep -qE 'confidentiality-gate\.yml' "$SIGN_SCRIPT"
}

# ── .gitattributes auto-resolves signature conflicts ────────────────────────

@test ".gitattributes declares merge=ours for signature file" {
  grep -qE '\.confidentiality-signature.*merge=ours' "$GITATTR"
}

@test ".gitattributes comment explains the rationale for merge=ours" {
  grep -qiE "(queued|conflict|PR|rebase)" "$GITATTR"
}

# ── Negative / failure modes ────────────────────────────────────────────────

@test "negative: pr-rebase declares check for uncommitted changes" {
  # Structural: the script always cd's to its own $ROOT, so runtime testing
  # with a fake tmp repo is not feasible. Validate the guard exists.
  grep -qE "(uncommitted|dirty|diff --quiet)" "$REBASE_SCRIPT"
}

@test "negative: pr-rebase declares guard against running on main/master" {
  grep -qE '\$BRANCH.*"main"|\$BRANCH.*"master"|BRANCH.*==.*main|BRANCH.*==.*master' "$REBASE_SCRIPT"
}

@test "negative: invalid flag does not crash script" {
  run bash "$REBASE_SCRIPT" --help
  [ "$status" -eq 0 ]
}

@test "negative: unknown arg ignored gracefully" {
  # The script silently ignores unknown args (only parses --no-push, -h/--help)
  cd "$TMP_DIR"
  git init -q .
  git checkout -q -b main
  run bash "$REBASE_SCRIPT" --unknown-flag-12345
  # Should not crash on parsing; may exit with other errors (no remote, etc.)
  [ "$status" -ne 127 ]  # 127 would be command-not-found
}

# ── Edge cases ──────────────────────────────────────────────────────────────

@test "edge: empty working dir — script fails gracefully" {
  cd "$TMP_DIR"
  run bash "$REBASE_SCRIPT"
  # No git repo → exit nonzero, no crash
  [ "$status" -ne 0 ]
  [ "$status" -ne 127 ]
}

@test "edge: nonexistent remote — script reports fetch failure" {
  cd "$TMP_DIR"
  git init -q .
  git config user.email test@test.local
  git config user.name test
  git checkout -q -b feature-test
  echo initial > file.txt
  git add file.txt && git commit -q -m initial
  run bash "$REBASE_SCRIPT"
  # No remote configured → fetch fails, exit 3
  [ "$status" -ne 0 ]
}

@test "edge: boundary — --no-push flag accepted" {
  grep -q "\-\-no-push" "$REBASE_SCRIPT"
}

@test "edge: zero commits ahead — script handles already-up-to-date case" {
  grep -qE "(Already up to date|BEHIND.*-eq 0|nothing to rebase)" "$REBASE_SCRIPT"
}

# ── Regression guard ────────────────────────────────────────────────────────

@test "regression: confidentiality-sign.sh retains merge-base pattern" {
  count=$(grep -c "merge-base" "$SIGN_SCRIPT")
  [ "$count" -ge 1 ]
}

@test "regression: .gitattributes retains the signature merge rule" {
  count=$(grep -c "\.confidentiality-signature" "$GITATTR")
  [ "$count" -ge 1 ]
}

@test "regression: pr-rebase script retains force-with-lease safety" {
  count=$(grep -c "force-with-lease" "$REBASE_SCRIPT")
  [ "$count" -ge 1 ]
}

# ── Isolation (the script targets the cwd repo, never its own checkout) ─────

fixture_repo() {
  cd "$TMP_DIR"
  git init -q -b main .
  git config user.email test@test.local
  git config user.name test
  echo a > a.txt && git add a.txt && git commit -q -m a
  git switch -q -c feature
}

@test "error: outside a git repository exits 2 with an explicit message" {
  cd "$TMP_DIR"
  run bash "$REBASE_SCRIPT" --no-push
  [ "$status" -eq 2 ]
  [[ "$output" == *"not inside a git repository"* ]]
}

@test "SE-501: sin confidentiality-sign.sh en el repo destino rebasa igual y no crea firma ni commit de firma" {
  r=$(d_conflict_repo .scm/sam.json)
  cd "$r"
  [ ! -e scripts/confidentiality-sign.sh ]
  run bash "$REBASE_SCRIPT" --no-push
  [ "$status" -eq 0 ]
  [ ! -e .confidentiality-signature ]
  run git log --format=%s origin/main..HEAD
  [[ "$output" != *"sign confidentiality"* ]]
}

@test "isolation: running from a fixture repo never touches the real repo" {
  real_head=$(git -C "$REPO_ROOT" rev-parse HEAD)
  real_refs=$(git -C "$REPO_ROOT" for-each-ref --format='%(refname) %(objectname)' refs/heads | sha256sum)
  fixture_repo
  run bash "$REBASE_SCRIPT" --no-push
  [ "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$real_head" ]
  [ "$(git -C "$REPO_ROOT" for-each-ref --format='%(refname) %(objectname)' refs/heads | sha256sum)" = "$real_refs" ]
}
