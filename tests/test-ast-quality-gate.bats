#!/usr/bin/env bats
# SE-376 wave1 — consolidacion ast-quality-gate
S=".claude/skills/ast-quality-gate/SKILL.md"
D=".claude/skills/ast-quality-gate/DOMAIN.md"
@test "[ast-quality-gate] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[ast-quality-gate] DOMAIN presente" { [ -f "$D" ]; }
@test "[ast-quality-gate] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
