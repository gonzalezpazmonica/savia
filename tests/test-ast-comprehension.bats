#!/usr/bin/env bats
# SE-376 wave1 — consolidacion ast-comprehension
S=".claude/skills/ast-comprehension/SKILL.md"
D=".claude/skills/ast-comprehension/DOMAIN.md"
@test "[ast-comprehension] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[ast-comprehension] DOMAIN presente" { [ -f "$D" ]; }
@test "[ast-comprehension] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
