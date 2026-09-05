#!/usr/bin/env bats
# SE-376 wave1 — consolidacion sprint-management
S=".claude/skills/sprint-management/SKILL.md"
D=".claude/skills/sprint-management/DOMAIN.md"
@test "[sprint-management] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[sprint-management] DOMAIN presente" { [ -f "$D" ]; }
@test "[sprint-management] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
