#!/usr/bin/env bats
# SE-376 wave1 — consolidacion onboarding-dev
S=".claude/skills/onboarding-dev/SKILL.md"
D=".claude/skills/onboarding-dev/DOMAIN.md"
@test "[onboarding-dev] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[onboarding-dev] DOMAIN presente" { [ -f "$D" ]; }
@test "[onboarding-dev] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
