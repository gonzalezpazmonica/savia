#!/usr/bin/env bats
# SE-376 wave1 — consolidacion understand-anything
S=".claude/skills/understand-anything/SKILL.md"
D=".claude/skills/understand-anything/DOMAIN.md"
@test "[understand-anything] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[understand-anything] DOMAIN presente" { [ -f "$D" ]; }
@test "[understand-anything] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
