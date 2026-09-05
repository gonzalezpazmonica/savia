#!/usr/bin/env bats
# SE-376 wave1 — consolidacion savia-school
S=".claude/skills/savia-school/SKILL.md"
D=".claude/skills/savia-school/DOMAIN.md"
@test "[savia-school] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[savia-school] DOMAIN presente" { [ -f "$D" ]; }
@test "[savia-school] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
