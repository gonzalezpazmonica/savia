#!/usr/bin/env bats
# SE-376 wave1 — consolidacion pbi-decomposition
S=".claude/skills/pbi-decomposition/SKILL.md"
D=".claude/skills/pbi-decomposition/DOMAIN.md"
@test "[pbi-decomposition] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[pbi-decomposition] DOMAIN presente" { [ -f "$D" ]; }
@test "[pbi-decomposition] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
