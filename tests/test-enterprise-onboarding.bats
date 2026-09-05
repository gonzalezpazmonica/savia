#!/usr/bin/env bats
# SE-376 wave1 — consolidacion enterprise-onboarding
S=".claude/skills/enterprise-onboarding/SKILL.md"
D=".claude/skills/enterprise-onboarding/DOMAIN.md"
@test "[enterprise-onboarding] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[enterprise-onboarding] DOMAIN presente" { [ -f "$D" ]; }
@test "[enterprise-onboarding] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
