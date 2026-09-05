#!/usr/bin/env bats
# SE-376 wave1 — consolidacion codebase-map
S=".claude/skills/codebase-map/SKILL.md"
D=".claude/skills/codebase-map/DOMAIN.md"
@test "[codebase-map] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[codebase-map] DOMAIN presente" { [ -f "$D" ]; }
@test "[codebase-map] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
