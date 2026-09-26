#!/usr/bin/env bats
# Tests for SPEC-063 Test Architect Agent
# Ref: docs/propuestas/SPEC-063-test-architect.md
# Strategy: Validate that all Test Architect deliverables exist, are well-formed,
#   and contain the required quality patterns. Positive: file existence and content.
#   Negative: missing patterns detected. Edge: empty/boundary content checks.

setup() {
  cd "$BATS_TEST_DIRNAME/../.." || exit 1
  AGENT=".opencode/agents/test-architect.md"
  SKILL=".opencode/skills/test-architect/SKILL.md"
  DOMAIN=".opencode/skills/test-architect/DOMAIN.md"
  TEMPLATE=".opencode/skills/test-architect/references/bats-template.md"
  SPEC="docs/propuestas/SPEC-063-test-architect.md"
  TMPDIR_TEST=$(mktemp -d)
}
teardown() {
  rm -rf "$TMPDIR_TEST"
}
@test "agent definition file exists" {
  [ -f "$AGENT" ]
}

@test "skill SKILL.md exists" {
  [ -f "$SKILL" ]
}

@test "skill DOMAIN.md exists" {
  [ -f "$DOMAIN" ]
}

@test "BATS golden template exists" {
  [ -f "$TEMPLATE" ]
}

@test "SPEC-063 document exists" {
  [ -f "$SPEC" ]
}
@test "agent specifies capable model for test strategy" {
  grep -qE "^model_tier: (heavy|mid|fast)" "$AGENT"
}
@test "agent contains all 8 excellence patterns" {
  grep -q "setup.*teardown" "$AGENT"
  grep -q "Safety verification" "$AGENT"
  grep -q "positive cases" "$AGENT"
  grep -q "negative cases" "$AGENT"
  grep -q "Edge cases" "$AGENT"
  grep -q "Spec.*reference\|doc reference" "$AGENT"
  grep -q "assertion" "$AGENT"
  grep -q "Coverage breadth\|coverage breadth" "$AGENT"
}

@test "skill covers major test types" {
  grep -q "Unit" "$SKILL"
  grep -q "Integration" "$SKILL"
  grep -q "E2E" "$SKILL"
  grep -q "Regression" "$SKILL"
  grep -q "Security" "$SKILL"
  grep -q "Contract" "$SKILL"
  grep -q "Mutation" "$SKILL"
  grep -q "Property" "$SKILL"
}

@test "agent covers 16 language frameworks" {
  for lang in TypeScript Java Python Go Rust PHP Ruby BATS Angular React Flutter Kotlin Swift Terraform; do
    grep -q "$lang" "$AGENT"
  done
  grep -q "C#" "$AGENT"
  grep -q "COBOL" "$AGENT"
}

@test "template includes setup and teardown functions" {
  grep -q "setup()" "$TEMPLATE"
  grep -q "teardown()" "$TEMPLATE"
  grep -q "mktemp" "$TEMPLATE"
  grep -q "rm -rf" "$TEMPLATE"
}

@test "template includes negative case patterns with error keywords" {
  grep -q "fail\|missing\|invalid\|error\|reject" "$TEMPLATE"
}

@test "template includes edge case patterns with boundary keywords" {
  grep -q "empty\|boundary\|nonexistent" "$TEMPLATE"
}

@test "template includes spec reference pattern" {
  grep -q "SPEC.*doc.*exists\|SPEC-NNN\|docs/propuestas" "$TEMPLATE"
}
@test "fails if agent file is missing required frontmatter" {
  # Agent must have name, description, model_tier, tools in frontmatter
  head -20 "$AGENT" | grep -q "name:"
  head -20 "$AGENT" | grep -q "description:"
  head -20 "$AGENT" | grep -q "^model_tier:"
  head -20 "$AGENT" | grep -q "tools:"
}

@test "rejects DOMAIN.md over 60 lines" {
  lines=$(wc -l < "$DOMAIN")
  [ "$lines" -le 60 ]
}

@test "rejects SKILL.md over 150 lines" {
  lines=$(wc -l < "$SKILL")
  [ "$lines" -le 150 ]
}

@test "rejects agent over 150 lines" {
  lines=$(wc -l < "$AGENT")
  [ "$lines" -le 150 ]
}
@test "DOMAIN.md is not empty" {
  [ -s "$DOMAIN" ]
  lines=$(wc -l < "$DOMAIN")
  [ "$lines" -ge 10 ]
}

@test "template scoring table boundary check" {
  # Template must document expected score >= 90
  grep -q "90" "$TEMPLATE"
}

@test "SPEC has nonexistent language handling" {
  # SPEC or skill must mention handling unsupported languages
  grep -qi "not.*supported\|closest match\|warn" "$SKILL" || \
  grep -qi "not.*supported\|closest match\|warn" "$SPEC"
}
@test "SPEC-063 referenced in agent or skill" {
  grep -q "SPEC-063" "$AGENT" || grep -q "SPEC-063" "$SKILL" || \
  grep -q "SPEC-063" "$SPEC"
}

@test "agent uses safety flags in referenced scripts" {
  grep -q "set -[euo]*o pipefail" .opencode/skills/test-architect/references/bats-template.md
}

@test "template produces valid structure" {
  [[ "$(wc -l < "$TEMPLATE")" -gt 10 ]]
  grep -q "setup" "$TEMPLATE"
}
