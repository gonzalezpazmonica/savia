#!/usr/bin/env bats
# SE-376 wave1 — consolidacion risk-scoring
S=".claude/skills/risk-scoring/SKILL.md"
D=".claude/skills/risk-scoring/DOMAIN.md"
@test "[risk-scoring] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[risk-scoring] DOMAIN presente" { [ -f "$D" ]; }
@test "[risk-scoring] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
