#!/usr/bin/env bats
# SE-376 wave1 — consolidacion orgchart-import
S=".claude/skills/orgchart-import/SKILL.md"
D=".claude/skills/orgchart-import/DOMAIN.md"
@test "[orgchart-import] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[orgchart-import] DOMAIN presente" { [ -f "$D" ]; }
@test "[orgchart-import] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
