#!/usr/bin/env bats
# SE-376 wave1 — consolidacion enterprise-analytics
S=".claude/skills/enterprise-analytics/SKILL.md"
D=".claude/skills/enterprise-analytics/DOMAIN.md"
@test "[enterprise-analytics] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[enterprise-analytics] DOMAIN presente" { [ -f "$D" ]; }
@test "[enterprise-analytics] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
