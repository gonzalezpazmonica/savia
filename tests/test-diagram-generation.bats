#!/usr/bin/env bats
# SE-376 wave1 — consolidacion diagram-generation
S=".claude/skills/diagram-generation/SKILL.md"
D=".claude/skills/diagram-generation/DOMAIN.md"
@test "[diagram-generation] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[diagram-generation] DOMAIN presente" { [ -f "$D" ]; }
@test "[diagram-generation] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
