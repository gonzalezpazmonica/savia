#!/usr/bin/env bats
# SE-376 wave1 — consolidacion legal-compliance
S=".claude/skills/legal-compliance/SKILL.md"
D=".claude/skills/legal-compliance/DOMAIN.md"
@test "[legal-compliance] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[legal-compliance] DOMAIN presente" { [ -f "$D" ]; }
@test "[legal-compliance] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
