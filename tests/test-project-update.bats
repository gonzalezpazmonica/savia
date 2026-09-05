#!/usr/bin/env bats
# SE-376 wave1 — consolidacion project-update
S=".claude/skills/project-update/SKILL.md"
D=".claude/skills/project-update/DOMAIN.md"
@test "[project-update] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[project-update] DOMAIN presente" { [ -f "$D" ]; }
@test "[project-update] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
