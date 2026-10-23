#!/usr/bin/env bats
# tests/bats/test-se255-push-gate.bats — SE-255 Push Gate
# Ref: SE-255 Push Gate
set -uo pipefail
#
# Tests para gate-init, gate-teardown, gate-post-receive, y pr-plan --gate-mode

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT_DIR="$REPO_ROOT/scripts"

  GATE_INIT="$SCRIPT_DIR/gate-init.sh"
  GATE_TEARDOWN="$SCRIPT_DIR/gate-teardown.sh"
  GATE_HOOK="$SCRIPT_DIR/gate-post-receive.sh"
  PR_PLAN="$SCRIPT_DIR/pr-plan.sh"

  # Create a disposable git repo for testing
  TMPDIR="$(mktemp -d)"
  cd "$TMPDIR"
  git init --quiet
  git config user.email "test@example.com"
  git config user.name "Test Runner"
  echo "test" > README.md
  git add README.md && git commit -m "initial" --quiet

  # Create a fake "GitHub" remote (another bare repo)
  FAKE_UPSTREAM="$TMPDIR/upstream.git"
  git init --bare --quiet "$FAKE_UPSTREAM"
  git remote add origin "$FAKE_UPSTREAM"
  git push origin main --quiet 2>/dev/null || true

  # Copy the gate scripts into the test repo so they're available
  mkdir -p "$TMPDIR/scripts"
  cp "$GATE_INIT" "$TMPDIR/scripts/gate-init.sh"
  cp "$GATE_TEARDOWN" "$TMPDIR/scripts/gate-teardown.sh"
  cp "$GATE_HOOK" "$TMPDIR/scripts/gate-post-receive.sh"
  cp "$PR_PLAN" "$TMPDIR/scripts/pr-plan.sh" 2>/dev/null || true
  # pr-plan-gates.sh is sourced by pr-plan.sh
  cp "$REPO_ROOT/scripts/pr-plan-gates.sh" "$TMPDIR/scripts/pr-plan-gates.sh" 2>/dev/null || true
  # confidentiality-sign.sh is called by the hook
  cp "$REPO_ROOT/scripts/confidentiality-sign.sh" "$TMPDIR/scripts/confidentiality-sign.sh" 2>/dev/null || true
  # savia-env.sh is sourced by some scripts
  cp "$REPO_ROOT/scripts/savia-env.sh" "$TMPDIR/scripts/savia-env.sh" 2>/dev/null || true
  # session-action-log.sh + execution-supervisor.sh are called by pr-plan
  cp "$REPO_ROOT/scripts/session-action-log.sh" "$TMPDIR/scripts/session-action-log.sh" 2>/dev/null || true
  cp "$REPO_ROOT/scripts/execution-supervisor.sh" "$TMPDIR/scripts/execution-supervisor.sh" 2>/dev/null || true
  mkdir -p "$TMPDIR/output"

  # Override GATE_DIR for testing
  GATE_DIR="$TMPDIR/gate.git"
  export SAVIA_GATE_DIR="$GATE_DIR"

  # Override HOME for confidentiality-sign.sh
  export HOME="$TMPDIR/home"
  mkdir -p "$HOME/.savia"
}

teardown() {
  rm -rf "$TMPDIR"
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-1: Init configura el gate correctamente
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-1.1: gate-init.sh renombra origin -> origin-upstream" {
  run bash "$TMPDIR/scripts/gate-init.sh"
  [ "$status" -eq 0 ]

  run git remote get-url origin-upstream
  [ "$status" -eq 0 ]
  [[ "$output" == "$FAKE_UPSTREAM" ]]
}

@test "AC-1.2: gate-init.sh crea bare repo gate" {
  run bash "$TMPDIR/scripts/gate-init.sh"
  [ "$status" -eq 0 ]
  [ -d "$GATE_DIR" ]
  [ -f "$GATE_DIR/HEAD" ]
}

@test "AC-1.3: gate-init.sh instala post-receive hook ejecutable" {
  run bash "$TMPDIR/scripts/gate-init.sh"
  [ "$status" -eq 0 ]
  [ -f "$GATE_DIR/hooks/post-receive" ]
  [ -x "$GATE_DIR/hooks/post-receive" ]
}

@test "AC-1.4: gate-init.sh apunta origin al bare repo local" {
  run bash "$TMPDIR/scripts/gate-init.sh"
  [ "$status" -eq 0 ]

  origin_url=$(git remote get-url origin)
  [[ "$origin_url" == "$GATE_DIR" ]]
}

@test "AC-1.5: gate-init.sh registra metadata" {
  run bash "$TMPDIR/scripts/gate-init.sh"
  [ "$status" -eq 0 ]

  run git config --get savia.gate.enabled
  [ "$status" -eq 0 ]
  [[ "$output" == "true" ]]
}

@test "AC-1.6: gate-init.sh es idempotente" {
  bash "$TMPDIR/scripts/gate-init.sh"
  run bash "$TMPDIR/scripts/gate-init.sh"
  # Second run should skip, exit 0
  [[ "$output" == *"SKIP"* ]]
  [ "$status" -eq 0 ]
}

@test "AC-1.7: gate-init.sh --dry-run no modifica remotes" {
  origin_before=$(git remote get-url origin)
  run bash "$TMPDIR/scripts/gate-init.sh" --dry-run
  [ "$status" -eq 0 ]
  origin_after=$(git remote get-url origin)
  [[ "$origin_before" == "$origin_after" ]]
}

@test "AC-1.8: gate-init.sh rejects invalid path with graceful error" {
  run env SAVIA_GATE_DIR="/invalid/path" bash "$TMPDIR/scripts/gate-init.sh"
  [ "$status" -ne 0 ]
}

@test "AC-1.9: gate-init.sh handles empty SAVIA_GATE_DIR" {
  run env SAVIA_GATE_DIR="" bash "$TMPDIR/scripts/gate-init.sh"
  [ "$status" -ne 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-2: El gate bloquea pushes que no pasan pr-plan
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-2.1: pr-plan --gate-mode sale con exit 1 si hay FAIL" {
  # Create a broken commit (e.g., add a 151-line command file)
  mkdir -p "$TMPDIR/.opencode/commands"
  python3 -c "
for i in range(152):
    print(f'line {i}')
" > "$TMPDIR/.opencode/commands/oversized.md"
  git add .opencode/commands/oversized.md
  git commit -m "add oversized command" --quiet

  # pr-plan --gate-mode should detect this via G10 (validate-ci-local checks sizes)
  # Note: this is a best-effort test. The exact gate that catches it depends on
  # what checks run in the test environment.
  run bash "$TMPDIR/scripts/pr-plan.sh" --gate-mode
  # En modo gate un FAIL termina con 1 y lo nombra; un 0 aquí dejaría pasar el push.
  [ "$status" -eq 1 ]
  [[ "$output" == *"GATE: FAILED"* || "$output" == *"FAIL"* ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-4: Teardown revierte todo
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-4.1: gate-teardown.sh restaura origin -> upstream" {
  upstream_url=$(git remote get-url origin)
  bash "$TMPDIR/scripts/gate-init.sh"

  run bash "$TMPDIR/scripts/gate-teardown.sh"
  [ "$status" -eq 0 ]

  origin_url=$(git remote get-url origin)
  [[ "$origin_url" == "$upstream_url" ]]
}

@test "AC-4.2: gate-teardown.sh elimina la config savia.gate.*" {
  bash "$TMPDIR/scripts/gate-init.sh"
  bash "$TMPDIR/scripts/gate-teardown.sh"

  run git config --get savia.gate.enabled
  [ "$status" -ne 0 ]
}

@test "AC-4.3: tras teardown, git push origin va directo al upstream" {
  bash "$TMPDIR/scripts/gate-init.sh"
  bash "$TMPDIR/scripts/gate-teardown.sh"

  origin_url=$(git remote get-url origin)
  [[ "$origin_url" == "$FAKE_UPSTREAM" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-5: Compatibilidad
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-5.1: gate-teardown maneja estado sin gate (skip)" {
  run bash "$TMPDIR/scripts/gate-teardown.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "AC-5.2: gate-teardown --dry-run no modifica nada" {
  bash "$TMPDIR/scripts/gate-init.sh"
  origin_before=$(git remote get-url origin)
  run bash "$TMPDIR/scripts/gate-teardown.sh" --dry-run
  [ "$status" -eq 0 ]
  origin_after=$(git remote get-url origin)
  [[ "$origin_before" == "$origin_after" ]]
}

@test "AC-5.3: teardown on boundary state (no gate configured) succeeds" {
  run bash "$TMPDIR/scripts/gate-teardown.sh"
  [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# AC-6: Gate hook
# ─────────────────────────────────────────────────────────────────────────────

@test "AC-6.1: gate-post-receive.sh existe y es ejecutable" {
  [ -f "$GATE_HOOK" ]
  [ -x "$GATE_HOOK" ]
}

@test "AC-6.2: hook usa set -euo pipefail" {
  grep -q "set -euo pipefail" "$GATE_HOOK"
}

@test "AC-6.3: hook tiene trap EXIT para limpiar worktree" {
  grep -q "trap.*EXIT" "$GATE_HOOK"
}
