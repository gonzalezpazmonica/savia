#!/usr/bin/env bats
# SE-376 wave1 — consolidacion spec-driven-development
S=".claude/skills/spec-driven-development/SKILL.md"
D=".claude/skills/spec-driven-development/DOMAIN.md"
@test "[spec-driven-development] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[spec-driven-development] DOMAIN presente" { [ -f "$D" ]; }
@test "[spec-driven-development] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
