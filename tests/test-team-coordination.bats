#!/usr/bin/env bats
# SE-376 wave1 — consolidacion team-coordination
S=".claude/skills/team-coordination/SKILL.md"
D=".claude/skills/team-coordination/DOMAIN.md"
@test "[team-coordination] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[team-coordination] DOMAIN presente" { [ -f "$D" ]; }
@test "[team-coordination] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
