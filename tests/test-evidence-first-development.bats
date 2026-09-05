#!/usr/bin/env bats
# SE-376 wave1 — consolidacion evidence-first-development
S=".claude/skills/evidence-first-development/SKILL.md"
D=".claude/skills/evidence-first-development/DOMAIN.md"
@test "[evidence-first-development] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[evidence-first-development] DOMAIN presente" { [ -f "$D" ]; }
@test "[evidence-first-development] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
