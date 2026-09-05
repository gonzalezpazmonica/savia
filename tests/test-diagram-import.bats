#!/usr/bin/env bats
# SE-376 wave1 — consolidacion diagram-import
S=".claude/skills/diagram-import/SKILL.md"
D=".claude/skills/diagram-import/DOMAIN.md"
@test "[diagram-import] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[diagram-import] DOMAIN presente" { [ -f "$D" ]; }
@test "[diagram-import] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
