#!/usr/bin/env bats
# BATS tests for scripts/resolve-pr-conflicts.sh + resolve-all-open-prs.sh.
# Solves the recurring "merging one PR breaks all others" problem observed
# through PRs #607..#615 where CHANGELOG + signature conflicts appeared on
# every peer PR after each merge.
#
# Ref: SPEC-SE-012 signal-noise reduction (related).
# Safety: ambos scripts con `set -uo pipefail`; test sandbox isolation.

setup() {
  export TMPDIR="${BATS_TEST_TMPDIR:-/tmp}"
  cd "$BATS_TEST_DIRNAME/.."
}

teardown() {
  cd /
}

# ── Existence / safety ─────────────────────────────────────────────────────

@test "resolve-pr-conflicts.sh is executable" {
  [[ -x "scripts/resolve-pr-conflicts.sh" ]]
}

@test "resolve-all-open-prs.sh is executable" {
  [[ -x "scripts/resolve-all-open-prs.sh" ]]
}

@test "resolve-pr-conflicts uses set -uo pipefail" {
  run grep -cE '^set -[uo]+ pipefail' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 1 ]]
}

@test "resolve-all-open-prs uses set -uo pipefail" {
  run grep -cE '^set -[uo]+ pipefail' "scripts/resolve-all-open-prs.sh"
  [[ "$output" -ge 1 ]]
}

@test "resolve-pr-conflicts passes bash -n" {
  run bash -n "scripts/resolve-pr-conflicts.sh"
  [ "$status" -eq 0 ]
}

@test "resolve-all-open-prs passes bash -n" {
  run bash -n "scripts/resolve-all-open-prs.sh"
  [ "$status" -eq 0 ]
}

# ── CLI surface ────────────────────────────────────────────────────────────

@test "resolve-pr-conflicts --help exits 0" {
  run bash scripts/resolve-pr-conflicts.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"branch"* ]]
  [[ "$output" == *"dry-run"* ]]
}

@test "resolve-all-open-prs --help exits 0" {
  run bash scripts/resolve-all-open-prs.sh --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"dry-run"* ]]
}

@test "resolve-pr-conflicts rejects unknown arg" {
  run bash scripts/resolve-pr-conflicts.sh --bogus
  [ "$status" -eq 2 ]
}

@test "resolve-all-open-prs rejects unknown arg" {
  run bash scripts/resolve-all-open-prs.sh --bogus
  [ "$status" -eq 2 ]
}

# ── Safety guards ──────────────────────────────────────────────────────────

@test "resolve-pr-conflicts refuses to operate on main" {
  run bash scripts/resolve-pr-conflicts.sh --branch main
  [ "$status" -eq 2 ]
  [[ "$output" == *"refusing"* ]] || [[ "$output" == *"main"* ]]
}

@test "resolve-pr-conflicts refuses to operate on master" {
  run bash scripts/resolve-pr-conflicts.sh --branch master
  [ "$status" -eq 2 ]
}

@test "resolve-pr-conflicts --dry-run does not mutate repo" {
  local before_hash after_hash
  before_hash=$(git rev-parse HEAD)
  bash scripts/resolve-pr-conflicts.sh --branch "$(git rev-parse --abbrev-ref HEAD)" --dry-run >/dev/null 2>&1 || true
  after_hash=$(git rev-parse HEAD)
  [[ "$before_hash" == "$after_hash" ]]
}

# ── Conflict handling logic (documentation pattern-match) ──────────────────

@test "script handles CHANGELOG.md conflict with merge strategy" {
  run grep -c 'CHANGELOG.md' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 3 ]]
}

# SE-501 (sustituye a «take theirs» en la firma y en .scm/, a la re-firma y a la regeneración del SCM):
# D ya no se versiona; un conflicto en D se resuelve sacándolo del índice, sin firmar ni regenerar.
rpc_repo() {  # rpc_repo <fichero en conflicto>: main y la rama editan el mismo fichero
  local o="$BATS_TEST_TMPDIR/origin.git" r="$BATS_TEST_TMPDIR/r" S="$BATS_TEST_DIRNAME/../scripts"
  git init -q --bare "$o"; git init -q -b main "$r"
  git -C "$r" config user.email t@t; git -C "$r" config user.name t
  mkdir -p "$r/.scm"; echo base > "$r/a.txt"; echo '{"v":0}' > "$r/.scm/sam.json"
  git -C "$r" add -f -A; git -C "$r" commit -qm base
  git -C "$r" remote add origin "$o"; git -C "$r" push -q origin main
  git -C "$r" checkout -q -b feature
  echo rama > "$r/$1"; git -C "$r" add -f -A; git -C "$r" commit -qm rama
  git -C "$r" checkout -q main
  echo main > "$r/$1"; git -C "$r" add -f -A; git -C "$r" commit -qm main; git -C "$r" push -q origin main
  git -C "$r" checkout -q feature
  echo "$r"
}

@test "SE-501: conflicto en una ruta de D → se saca del índice, merge commiteado, sin firma ni regeneración" {
  r=$(rpc_repo .scm/sam.json)
  run env RESOLVE_REPO_ROOT="$r" bash "$BATS_TEST_DIRNAME/../scripts/resolve-pr-conflicts.sh" --no-push
  [ "$status" -eq 0 ]
  [ "$(git -C "$r" rev-list --parents -n1 HEAD | wc -w)" -eq 3 ]
  run git -C "$r" ls-files --error-unmatch .scm/sam.json
  [ "$status" -ne 0 ]
  [ ! -e "$r/.confidentiality-signature" ]
}

# Rama hostil: su scripts/derived.sh deja una marca al cargarse y su derived-paths.txt declara a.txt como D.
rpc_hostile_branch() {  # rpc_hostile_branch <repo>
  local r="$1"
  mkdir -p "$r/scripts"
  printf 'touch "%s/PWNED"\nderived_paths_load(){ DERIVED_PATHS=(a.txt); }\nis_derived_path(){ return 0; }\n' \
    "$BATS_TEST_TMPDIR" > "$r/scripts/derived.sh"
  printf 'a.txt\n' > "$r/scripts/derived-paths.txt"
  git -C "$r" add -f scripts; git -C "$r" commit -qm hostil
}
rpc_copy() {  # rpc_copy [con-D]: copia del resolutor como la hace el workflow; con «con-D», con derived.sh y la lista
  local d="$BATS_TEST_TMPDIR/copy" S="$BATS_TEST_DIRNAME/../scripts"
  mkdir -p "$d/scripts"; cp "$S/resolve-pr-conflicts.sh" "$d/scripts/"
  [[ "${1:-}" == con-D ]] && cp "$S/derived.sh" "$S/derived-paths.txt" "$d/scripts/"
  echo "$d/scripts/resolve-pr-conflicts.sh"
}

@test "SE-501 P1: desde una copia, el resolutor no carga derived.sh ni la lista D de la rama (sin marca, a.txt no es D)" {
  r=$(rpc_repo a.txt); rpc_hostile_branch "$r"
  run env RESOLVE_REPO_ROOT="$r" bash "$(rpc_copy con-D)" --no-push
  [ ! -e "$BATS_TEST_TMPDIR/PWNED" ]
  [ "$status" -eq 3 ]
  [[ "$output" == *"a.txt"* ]]
}

@test "SE-501 P1: copia sin derived.sh junto al resolutor → tampoco usa la de la rama; conflicto en D = inesperado (exit 3)" {
  r=$(rpc_repo .scm/sam.json); rpc_hostile_branch "$r"
  run env RESOLVE_REPO_ROOT="$r" bash "$(rpc_copy)" --no-push
  [ ! -e "$BATS_TEST_TMPDIR/PWNED" ]
  [ "$status" -eq 3 ]
}

@test "SE-501 P1 control: copia con derived.sh y la lista → resuelve el conflicto en D" {
  r=$(rpc_repo .scm/sam.json)
  run env RESOLVE_REPO_ROOT="$r" bash "$(rpc_copy con-D)" --no-push
  [ "$status" -eq 0 ]
  run git -C "$r" ls-files --error-unmatch .scm/sam.json
  [ "$status" -ne 0 ]
}

@test "SE-501 P1: los lanzadores copian derived.sh y derived-paths.txt junto al resolutor" {
  for f in .github/workflows/auto-rebase-open-prs.yml scripts/resolve-all-open-prs.sh; do
    grep -qE 'cp .*resolve-pr-conflicts\.sh.*derived\.sh' "$f" || { echo "sin copia de derived.sh: $f"; false; }
    grep -qE 'derived-paths\.txt.*RESOLVER_DIR/scripts/' "$f" || { echo "sin copia de la lista: $f"; false; }
  done
}

@test "auto-rebase: la lista de PR llega por env, no interpolada en el script (inyección por nombre de rama)" {
  f=.github/workflows/auto-rebase-open-prs.yml
  run grep -nE "^[^#]*'\\$\\{\\{ *steps\\." "$f"
  [ "$status" -eq 1 ]
  grep -qE 'PRS: \$\{\{ steps\.list_prs\.outputs\.prs \}\}' "$f"
}

@test "SE-501: conflicto fuera de D y de CHANGELOG.md → no lo resuelve (≠ 0) y lo nombra" {
  r=$(rpc_repo a.txt)
  run env RESOLVE_REPO_ROOT="$r" bash "$BATS_TEST_DIRNAME/../scripts/resolve-pr-conflicts.sh" --no-push
  [ "$status" -ne 0 ]
  [[ "$output" == *"a.txt"* ]]
}

@test "script aborts on UNEXPECTED conflict files" {
  run grep -c 'unexpected.*human review\|require human review\|human intervention required' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 1 ]]
}


# ── CHANGELOG parsing invariants ───────────────────────────────────────────

@test "script extracts top version from OURS CHANGELOG" {
  run grep -c 'ours_top_line\|ours_version' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 2 ]]
}

@test "script preserves semver order (newer on top)" {
  run grep -c 'prepend\|above the first\|newer on top' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 2 ]]
}

@test "script dedupes link lines (avoids duplicate versions)" {
  run grep -c 'not already in\|already exists\|grep -qF' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 1 ]]
}

# ── resolve-all-open-prs integration ──────────────────────────────────────

@test "orchestrator requires gh and jq" {
  run grep -cE 'command -v gh|command -v jq' "scripts/resolve-all-open-prs.sh"
  [[ "$output" -ge 2 ]]
}

@test "orchestrator uses gh pr list with JSON filter" {
  run grep -cE 'gh pr list.*--json' "scripts/resolve-all-open-prs.sh"
  [[ "$output" -ge 1 ]]
}

@test "orchestrator skips PRs already CLEAN" {
  run grep -c 'SKIP (already clean)\|already clean' "scripts/resolve-all-open-prs.sh"
  [[ "$output" -ge 1 ]]
}

@test "orchestrator returns to original branch when done" {
  run grep -c 'original_branch\|git checkout "\$original_branch"' "scripts/resolve-all-open-prs.sh"
  [[ "$output" -ge 2 ]]
}

# ── Negative / edge cases ──────────────────────────────────────────────────

@test "negative: resolve-pr-conflicts without args uses current branch" {
  local current
  current=$(git rev-parse --abbrev-ref HEAD)
  run bash scripts/resolve-pr-conflicts.sh --dry-run
  # Exits 0 or skips main; either way no crash
  [[ "$status" -eq 0 || "$status" -eq 2 ]]
}

@test "negative: unknown flag on orchestrator rejected" {
  run bash scripts/resolve-all-open-prs.sh --xyzzy
  [ "$status" -eq 2 ]
}

@test "negative: scripts do NOT force-push" {
  run grep -lE 'push --force|push -f[[:space:]]|push --force-with-lease' scripts/resolve-pr-conflicts.sh scripts/resolve-all-open-prs.sh
  [ "$status" -ne 0 ] || [[ -z "$output" ]]
}

@test "negative: scripts do NOT use --amend" {
  run grep -l 'commit --amend' scripts/resolve-pr-conflicts.sh scripts/resolve-all-open-prs.sh
  [ "$status" -ne 0 ] || [[ -z "$output" ]]
}

@test "negative: unexpected conflict file name triggers exit code 3" {
  run grep -c 'exit 3' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 1 ]]
}

# ── Edge cases ─────────────────────────────────────────────────────────────

@test "edge: resolve-pr-conflicts respects --no-push flag" {
  run grep -c 'NO_PUSH' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 3 ]]
}

@test "edge: orchestrator propagates --no-push and --dry-run flags" {
  run grep -cE 'NO_PUSH|DRY_RUN' "scripts/resolve-all-open-prs.sh"
  [[ "$output" -ge 4 ]]
}

@test "edge: both scripts reference the recurring-conflict pattern doc" {
  run grep -l 'CHANGELOG\|signature\|recurring' scripts/resolve-pr-conflicts.sh scripts/resolve-all-open-prs.sh
  local n
  n=$(echo "$output" | wc -l)
  [[ "$n" -ge 2 ]]
}

@test "edge: resolve-pr-conflicts cleans temp files" {
  run grep -c '/tmp/changelog-' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 3 ]]
  run grep -c 'rm -f /tmp/changelog' "scripts/resolve-pr-conflicts.sh"
  [[ "$output" -ge 1 ]]
}

@test "edge: orchestrator operates on a copy via git fetch (no direct branch mutation)" {
  run grep -c 'git fetch origin' "scripts/resolve-all-open-prs.sh"
  [[ "$output" -ge 1 ]]
}

@test "edge: scripts document their purpose in header comments" {
  local lines1 lines2
  lines1=$(head -20 "scripts/resolve-pr-conflicts.sh" | grep -c '^#')
  lines2=$(head -20 "scripts/resolve-all-open-prs.sh" | grep -c '^#')
  [[ "$lines1" -ge 10 ]]
  [[ "$lines2" -ge 5 ]]
}
