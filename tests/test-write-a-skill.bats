#!/usr/bin/env bats
# SE-376 wave1 — consolidacion write-a-skill
S=".claude/skills/write-a-skill/SKILL.md"
D=".claude/skills/write-a-skill/DOMAIN.md"
@test "[write-a-skill] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[write-a-skill] DOMAIN presente" { [ -f "$D" ]; }
@test "[write-a-skill] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
