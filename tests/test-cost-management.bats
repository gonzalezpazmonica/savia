#!/usr/bin/env bats
# SE-376 wave1 — consolidacion cost-management
S=".claude/skills/cost-management/SKILL.md"
D=".claude/skills/cost-management/DOMAIN.md"
@test "[cost-management] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[cost-management] DOMAIN presente" { [ -f "$D" ]; }
@test "[cost-management] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
