#!/usr/bin/env bats
# SE-376 wave1 — consolidacion governance-enterprise
S=".claude/skills/governance-enterprise/SKILL.md"
D=".claude/skills/governance-enterprise/DOMAIN.md"
@test "[governance-enterprise] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[governance-enterprise] DOMAIN presente" { [ -f "$D" ]; }
@test "[governance-enterprise] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
