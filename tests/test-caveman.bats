#!/usr/bin/env bats
# SE-376 wave1 — consolidacion caveman
S=".claude/skills/caveman/SKILL.md"
D=".claude/skills/caveman/DOMAIN.md"
@test "[caveman] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[caveman] DOMAIN presente" { [ -f "$D" ]; }
@test "[caveman] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
