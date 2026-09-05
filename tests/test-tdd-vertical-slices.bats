#!/usr/bin/env bats
# SE-376 wave1 — consolidacion tdd-vertical-slices
S=".claude/skills/tdd-vertical-slices/SKILL.md"
D=".claude/skills/tdd-vertical-slices/DOMAIN.md"
@test "[tdd-vertical-slices] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[tdd-vertical-slices] DOMAIN presente" { [ -f "$D" ]; }
@test "[tdd-vertical-slices] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
