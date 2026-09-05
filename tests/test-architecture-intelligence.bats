#!/usr/bin/env bats
# SE-376 wave1 — consolidacion architecture-intelligence
S=".claude/skills/architecture-intelligence/SKILL.md"
D=".claude/skills/architecture-intelligence/DOMAIN.md"
@test "[architecture-intelligence] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[architecture-intelligence] DOMAIN presente" { [ -f "$D" ]; }
@test "[architecture-intelligence] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
