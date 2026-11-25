#!/usr/bin/env bats
# test-se253-command-tiers.bats — SE-253 Slice 1: Command tier classification
#
# Tests:
# AC-1.1: extended commands count >= 45% of total (index reduction target)
# AC-1.2: catalog.md exists and has tier:core
# AC-1.3: Existing bats tests were not modified by this slice (suite count unchanged)
# AC-1.4: command-tier-audit.sh exists and is executable
# AC-1.5: At least 1 command has tier:extended (classification applied)
# Extra:  All critical commands (sprint-*, daily-*, pr-plan, help) are core

COMMANDS_DIR="${BATS_TEST_DIRNAME}/../../.claude/commands"
SCRIPTS_DIR="${BATS_TEST_DIRNAME}/../../scripts"
TESTS_DIR="${BATS_TEST_DIRNAME}"

# Helper: extract tier from a command .md file
get_tier() {
  local filepath="$1"
  awk '
    BEGIN { in_front=0 }
    /^---/ { if (in_front==0) { in_front=1; next } else { exit } }
    in_front && /^tier:/ { gsub(/^tier:[[:space:]]*/, ""); gsub(/[[:space:]]*$/, ""); print; exit }
  ' "$filepath"
}

# Helper: count commands with a specific tier
count_tier() {
  local tier="$1"
  local count=0
  for f in "$COMMANDS_DIR"/*.md; do
    t="$(get_tier "$f")"
    [ "$t" = "$tier" ] && (( count++ )) || true
  done
  echo "$count"
}

# ---------------------------------------------------------------------------
# AC-1.1: extended commands >= 45% of total (index reduction target)
# ---------------------------------------------------------------------------
@test "AC-1.1: extended commands >= 45% of total (index reduction >= 45%)" {
  ext_count="$(count_tier extended)"
  total=$(find "$COMMANDS_DIR" -name "*.md" -maxdepth 1 | wc -l)
  pct=$(( ext_count * 100 / total ))
  echo "extended: $ext_count / $total = ${pct}%"
  [ "$pct" -ge 45 ]
}

@test "AC-1.1: core commands count <= 320 (reasonable upper bound)" {
  core_count="$(count_tier core)"
  echo "core commands: $core_count"
  [ "$core_count" -le 320 ]
}

# ---------------------------------------------------------------------------
# AC-1.2: catalog.md exists and has tier:core
# ---------------------------------------------------------------------------
@test "AC-1.2: catalog.md exists" {
  [ -f "$COMMANDS_DIR/catalog.md" ]
}

@test "AC-1.2: catalog.md has tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/catalog.md")"
  echo "catalog.md tier: $tier"
  [ "$tier" = "core" ]
}

# ---------------------------------------------------------------------------
# AC-1.3: Suite integrity — no pre-existing bats file was mass-deleted
# ---------------------------------------------------------------------------
@test "AC-1.3: Existing bats tests directory has >= 40 test files (no mass deletion)" {
  count=$(find "$TESTS_DIR" -name "*.bats" | wc -l)
  echo "total bats files: $count"
  [ "$count" -ge 40 ]
}

@test "AC-1.3: se253 slice 1 bats file exists (this file)" {
  [ -f "$TESTS_DIR/test-se253-command-tiers.bats" ]
}

# ---------------------------------------------------------------------------
# AC-1.4: command-tier-audit.sh exists and is executable
# ---------------------------------------------------------------------------
@test "AC-1.4: command-tier-audit.sh exists" {
  [ -f "$SCRIPTS_DIR/command-tier-audit.sh" ]
}

@test "AC-1.4: command-tier-audit.sh is executable" {
  [ -x "$SCRIPTS_DIR/command-tier-audit.sh" ]
}

@test "AC-1.4: command-tier-audit.sh --stats runs without error" {
  run bash "$SCRIPTS_DIR/command-tier-audit.sh" --stats
  echo "status: $status"
  echo "output: $output"
  [ "$status" -eq 0 ]
}

@test "AC-1.4: command-tier-audit.sh --stats output shows extended count > 0" {
  run bash "$SCRIPTS_DIR/command-tier-audit.sh" --stats
  echo "output: $output"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "extended"
  ext_num=$(echo "$output" | grep "extended" | grep -o '[0-9]*' | head -1)
  echo "extended count from stats: $ext_num"
  [ "${ext_num:-0}" -gt 0 ]
}

# ---------------------------------------------------------------------------
# AC-1.5: At least 1 command has tier:extended
# ---------------------------------------------------------------------------
@test "AC-1.5: At least 1 command has tier:extended" {
  ext_count="$(count_tier extended)"
  echo "extended commands: $ext_count"
  [ "$ext_count" -ge 1 ]
}

@test "AC-1.5: extended commands count >= 200 (substantial classification applied)" {
  ext_count="$(count_tier extended)"
  echo "extended commands: $ext_count"
  [ "$ext_count" -ge 200 ]
}

# ---------------------------------------------------------------------------
# Extra: critical commands are tier:core
# ---------------------------------------------------------------------------
@test "Extra: sprint-status is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/sprint-status.md")"
  echo "sprint-status tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: daily-routine is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/daily-routine.md")"
  echo "daily-routine tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: pr-plan is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/pr-plan.md")"
  echo "pr-plan tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: help is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/help.md")"
  echo "help tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: my-sprint is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/my-sprint.md")"
  echo "my-sprint tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: savia-live is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/savia-live.md")"
  echo "savia-live tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: board-flow is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/board-flow.md")"
  echo "board-flow tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: savia-shield is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/savia-shield.md")"
  echo "savia-shield tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: index-compact is tier:core" {
  tier="$(get_tier "$COMMANDS_DIR/index-compact.md")"
  echo "index-compact tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: catalog.md is tier:core (new SE-253 command)" {
  tier="$(get_tier "$COMMANDS_DIR/catalog.md")"
  echo "catalog tier: $tier"
  [ "$tier" = "core" ]
}

@test "Extra: total commands count is >= 557 (567 tras SE-253, menos 10 retiradas a propósito)" {
  # Suelo = recuento tras las retiradas legítimas: 3 órdenes marketplace-*
  # (SE-535 S1, PR #1658) y 7 ua-* (SE-535 S2, PR #1660). 567 - 10 = 557.
  # Sigue detectando borrados accidentales: cualquier pérdida adicional falla.
  total=$(find "$COMMANDS_DIR" -name "*.md" -maxdepth 1 | wc -l)
  echo "total commands: $total"
  [ "$total" -ge 557 ]
}

@test "Extra: every command .md has a tier field in frontmatter" {
  missing=0
  for f in "$COMMANDS_DIR"/*.md; do
    t="$(get_tier "$f")"
    if [ -z "$t" ]; then
      (( missing++ )) || true
      echo "Missing tier: $(basename $f)"
    fi
  done
  echo "Missing tier count: $missing"
  [ "$missing" -eq 0 ]
}

@test "Extra: all tier values are either 'core' or 'extended'" {
  bad=0
  for f in "$COMMANDS_DIR"/*.md; do
    t="$(get_tier "$f")"
    if [ "$t" != "core" ] && [ "$t" != "extended" ]; then
      (( bad++ )) || true
      echo "Bad tier '$t' in: $(basename $f)"
    fi
  done
  [ "$bad" -eq 0 ]
}
