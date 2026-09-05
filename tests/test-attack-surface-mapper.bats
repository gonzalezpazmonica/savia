#!/usr/bin/env bats
# SE-376 wave1 — consolidacion attack-surface-mapper
S=".claude/skills/attack-surface-mapper/SKILL.md"
D=".claude/skills/attack-surface-mapper/DOMAIN.md"
@test "[attack-surface-mapper] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[attack-surface-mapper] DOMAIN presente" { [ -f "$D" ]; }
@test "[attack-surface-mapper] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
