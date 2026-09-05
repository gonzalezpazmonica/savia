#!/usr/bin/env bats
# SE-376 wave1 — consolidacion overnight-sprint
S=".claude/skills/overnight-sprint/SKILL.md"
D=".claude/skills/overnight-sprint/DOMAIN.md"
@test "[overnight-sprint] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[overnight-sprint] DOMAIN presente" { [ -f "$D" ]; }
@test "[overnight-sprint] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
