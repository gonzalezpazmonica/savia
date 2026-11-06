#!/usr/bin/env bats

setup() {
  TESTDIR=$(mktemp -d)
  SCRIPT="$BATS_TEST_DIRNAME/../scripts/containment-run.sh"
  CHECK="$BATS_TEST_DIRNAME/../scripts/containment-check.sh"
}

teardown() {
  rm -rf "$TESTDIR"
  [[ -n "${SHM_DIR:-}" && "$SHM_DIR" == /dev/shm/s03s-cls-* ]] && rm -rf "$SHM_DIR"
  return 0
}

@test "N-anfitrion runs on host" {
  run bash "$SCRIPT" N-anfitrion "echo host-ok"
  [ "$status" -eq 0 ]
  [[ "$output" == *"host-ok"* ]]
}

@test "N-contenido without Docker fails closed" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-contenido "echo test"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]] || [[ "$output" == *"not installed"* ]]
}

@test "N-hostil without Docker fails closed" {
  PATH=/nonexistent:$PATH run bash "$SCRIPT" N-hostil "echo test"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]] || [[ "$output" == *"not installed"* ]]
}

@test "Unknown level rejected" {
  run bash "$SCRIPT" N-unknown "echo test"
  [ "$status" -eq 2 ]
}

@test "container policy file exists" {
  [ -f "$BATS_TEST_DIRNAME/../containment/container-policy.json" ]
}

@test "Dockerfile.base exists and valid" {
  [ -f "$BATS_TEST_DIRNAME/../containment/Dockerfile.base" ]
  grep -q "FROM" "$BATS_TEST_DIRNAME/../containment/Dockerfile.base"
}

@test "session-container script exists and executable" {
  [ -f "$BATS_TEST_DIRNAME/../containment/session-container.sh" ]
  [ -x "$BATS_TEST_DIRNAME/../containment/session-container.sh" ]
}

@test "execution levels documented in policy" {
  [ -f "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md" ]
  grep -q "N-anfitrion" "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md"
  grep -q "N-contenido" "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md"
  grep -q "N-hostil" "$BATS_TEST_DIRNAME/../docs/rules/domain/execution-containment.md"
}

@test "classify-execution-level works" {
  run bash "$BATS_TEST_DIRNAME/../scripts/classify-execution-level.sh" --help 2>/dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: classify-execution-level.sh"* ]]
  [[ "$output" == *"N-anfitrion"* ]]
}

@test "safety: containment-run has set -uo pipefail" {
  head -2 "$SCRIPT" | grep -q "set -euo pipefail"
}

@test "safety: containment-check has set -uo pipefail" {
  head -2 "$CHECK" | grep -q "set -euo pipefail"
}

@test "safety: adversarial script has set -uo pipefail" {
  head -2 "$BATS_TEST_DIRNAME/../scripts/adversarial-containment.sh" | grep -q "set -euo pipefail"
}

# ── classify-execution-level.sh: behaviour on an isolated workspace (SE-292 S1) ──
# The classifier derives the workspace from its own location, so each test
# copies it into a throwaway git repo under $TESTDIR/ws.

_mk_ws() {
  WS="$TESTDIR/ws"
  mkdir -p "$WS/scripts"
  cp "$BATS_TEST_DIRNAME/../scripts/classify-execution-level.sh" "$WS/scripts/"
  CLS="$WS/scripts/classify-execution-level.sh"
  git -C "$WS" init -q
  printf 'echo human\n' > "$WS/human.sh"
  printf 'echo bot\n' > "$WS/bot.sh"
  printf 'echo new\n' > "$WS/untracked.sh"
  git -C "$WS" add human.sh scripts/classify-execution-level.sh
  git -C "$WS" -c user.name="Ana Dev" -c user.email=a@example.invalid commit -qm human
  git -C "$WS" add bot.sh
  git -C "$WS" -c user.name="Claude" -c user.email=c@example.invalid commit -qm bot
}

@test "classify: human-authored tracked script is N-anfitrion" {
  _mk_ws
  run bash "$CLS" "$WS/human.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "N-anfitrion: $WS/human.sh (human-authored, git-tracked)" ]
}

@test "classify: agent-authored tracked script is N-contenido" {
  _mk_ws
  run bash "$CLS" "$WS/bot.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "N-contenido: $WS/bot.sh (agent-authored)" ]
}

@test "classify: untracked script inside the workspace is N-contenido" {
  _mk_ws
  run bash "$CLS" "$WS/untracked.sh"
  [ "$output" = "N-contenido: $WS/untracked.sh (not git-tracked)" ]
}

@test "classify: relative path is resolved from the caller's directory, not the workspace root" {
  _mk_ws
  mkdir -p "$WS/sub"
  printf 'echo x\n' > "$WS/sub/human.sh"   # untracked; a tracked human.sh exists at the root
  cd "$WS/sub"
  run bash "$CLS" human.sh
  [ "$output" = "N-contenido: human.sh (not git-tracked)" ]
}

@test "classify: script in /tmp outside the workspace is N-hostil" {
  _mk_ws
  printf 'echo x\n' > "$TESTDIR/drop.sh"
  run bash "$CLS" "$TESTDIR/drop.sh"
  [ "$output" = "N-hostil: $TESTDIR/drop.sh (tmp path)" ]
}

@test "classify: sibling dir sharing the workspace prefix is outside (security)" {
  _mk_ws
  mkdir -p "$TESTDIR/ws-evil"
  printf 'echo x\n' > "$TESTDIR/ws-evil/payload.sh"
  run bash "$CLS" "$TESTDIR/ws-evil/payload.sh"
  [ "$output" = "N-hostil: $TESTDIR/ws-evil/payload.sh (tmp path)" ]
}

@test "classify: symlink inside the workspace to an outside file is N-hostil" {
  _mk_ws
  printf 'echo x\n' > "$TESTDIR/target.sh"
  ln -s "$TESTDIR/target.sh" "$WS/link.sh"
  run bash "$CLS" "$WS/link.sh"
  [ "$output" = "N-hostil: $WS/link.sh (tmp path)" ]
}

@test "classify: script in /dev/shm (outside, world-writable) is N-hostil" {
  _mk_ws
  [ -d /dev/shm ] && [ -w /dev/shm ]   # precondition: Linux shared-memory dir
  SHM_DIR="$(mktemp -d /dev/shm/s03s-cls-XXXXXX)"
  printf 'echo x\n' > "$SHM_DIR/drop.sh"
  run bash "$CLS" "$SHM_DIR/drop.sh"
  [ "$output" = "N-hostil: $SHM_DIR/drop.sh (tmp path)" ]
}

@test "classify: unknown path outside workspace, tmp, home and third-party fails closed to N-hostil" {
  _mk_ws
  f=/etc/passwd   # exists everywhere, outside every known prefix
  [ -f "$f" ]
  run bash "$CLS" "$f"
  [ "$output" = "N-hostil: $f (outside workspace)" ]
}

@test "classify: third-party path inside the workspace is N-contenido" {
  _mk_ws
  mkdir -p "$WS/node_modules/pkg"
  printf 'x\n' > "$WS/node_modules/pkg/run.sh"
  run bash "$CLS" "$WS/node_modules/pkg/run.sh"
  [ "$output" = "N-contenido: $WS/node_modules/pkg/run.sh (third-party)" ]
}

@test "classify: third-party path outside the workspace stays N-contenido" {
  _mk_ws
  f=/usr/bin/env
  [ -f "$f" ]
  run bash "$CLS" "$f"
  [ "$output" = "N-contenido: $f (third-party)" ]
}

@test "classify: missing file reports UNKNOWN, never a level" {
  _mk_ws
  run bash "$CLS" "$WS/nope.sh"
  [ "$output" = "UNKNOWN: $WS/nope.sh (file not found)" ]
}

@test "classify --unclassified: undeclared agent and untracked scripts exit 1 with a count" {
  _mk_ws
  run bash "$CLS" --unclassified
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNCLASSIFIED: $WS/bot.sh (N-contenido"* ]]
  [[ "$output" == *"UNCLASSIFIED: $WS/untracked.sh (N-contenido"* ]]
  [[ "$output" == *"TOTAL UNCLASSIFIED: 2"* ]]
  [[ "$output" != *"UNCLASSIFIED: $WS/human.sh"* ]]
}

@test "classify --unclassified: scripts declared in the policy pass with exit 0" {
  _mk_ws
  mkdir -p "$WS/containment"
  printf '{"declared": ["bot.sh", "untracked.sh"]}\n' > "$WS/containment/container-policy.json"
  run bash "$CLS" --unclassified
  [ "$status" -eq 0 ]
  [[ "$output" == *"All scripts classified."* ]]
}

@test "classify --unclassified: boundary, exactly one undeclared script still exits 1" {
  _mk_ws
  mkdir -p "$WS/containment"
  printf '{"declared": ["bot.sh"]}\n' > "$WS/containment/container-policy.json"
  run bash "$CLS" --unclassified
  [ "$status" -eq 1 ]
  [[ "$output" == *"TOTAL UNCLASSIFIED: 1"* ]]
}

@test "classify: a tracked file of the real workspace is never N-hostil" {
  real="$BATS_TEST_DIRNAME/../scripts/classify-execution-level.sh"
  run bash "$real" "$(cd "$BATS_TEST_DIRNAME/.." && pwd)/scripts/containment-run.sh"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^N-(anfitrion|contenido):\ .*containment-run\.sh\ \(((human|agent)-authored|not\ git-tracked) ]]
}

@test "classify --inventory: counts every level and totals them" {
  _mk_ws
  run bash "$CLS" --inventory
  [ "$status" -eq 0 ]
  [[ "$output" == *"N-anfitrion: 2 | N-contenido: 2 | N-hostil: 0 | TOTAL: 4"* ]]
}
