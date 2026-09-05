#!/usr/bin/env bats
# SE-376 wave1 — consolidacion grill-me
S=".claude/skills/grill-me/SKILL.md"
D=".claude/skills/grill-me/DOMAIN.md"
@test "[grill-me] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[grill-me] DOMAIN presente" { [ -f "$D" ]; }
@test "[grill-me] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
