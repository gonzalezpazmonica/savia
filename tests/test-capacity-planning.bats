#!/usr/bin/env bats
# SE-376 wave1 — consolidacion capacity-planning
S=".claude/skills/capacity-planning/SKILL.md"
D=".claude/skills/capacity-planning/DOMAIN.md"
@test "[capacity-planning] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[capacity-planning] DOMAIN presente" { [ -f "$D" ]; }
@test "[capacity-planning] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
