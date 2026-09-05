#!/usr/bin/env bats
# SE-376 wave1 — consolidacion evaluations-framework
S=".claude/skills/evaluations-framework/SKILL.md"
D=".claude/skills/evaluations-framework/DOMAIN.md"
@test "[evaluations-framework] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[evaluations-framework] DOMAIN presente" { [ -f "$D" ]; }
@test "[evaluations-framework] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
