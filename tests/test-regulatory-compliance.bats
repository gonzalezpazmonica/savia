#!/usr/bin/env bats
# SE-376 wave1 — consolidacion regulatory-compliance
S=".claude/skills/regulatory-compliance/SKILL.md"
D=".claude/skills/regulatory-compliance/DOMAIN.md"
@test "[regulatory-compliance] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[regulatory-compliance] DOMAIN presente" { [ -f "$D" ]; }
@test "[regulatory-compliance] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
