#!/usr/bin/env bats
# SE-376 wave1 — consolidacion team-onboarding
S=".claude/skills/team-onboarding/SKILL.md"
D=".claude/skills/team-onboarding/DOMAIN.md"
@test "[team-onboarding] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[team-onboarding] DOMAIN presente" { [ -f "$D" ]; }
@test "[team-onboarding] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
