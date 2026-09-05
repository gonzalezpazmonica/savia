#!/usr/bin/env bats
# SE-376 wave1 — consolidacion savia-flow-practice
S=".claude/skills/savia-flow-practice/SKILL.md"
D=".claude/skills/savia-flow-practice/DOMAIN.md"
@test "[savia-flow-practice] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[savia-flow-practice] DOMAIN presente" { [ -f "$D" ]; }
@test "[savia-flow-practice] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
