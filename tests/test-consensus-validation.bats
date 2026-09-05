#!/usr/bin/env bats
# SE-376 wave1 — consolidacion consensus-validation
S=".claude/skills/consensus-validation/SKILL.md"
D=".claude/skills/consensus-validation/DOMAIN.md"
@test "[consensus-validation] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[consensus-validation] DOMAIN presente" { [ -f "$D" ]; }
@test "[consensus-validation] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
