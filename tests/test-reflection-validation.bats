#!/usr/bin/env bats
# SE-376 wave1 — consolidacion reflection-validation
S=".claude/skills/reflection-validation/SKILL.md"
D=".claude/skills/reflection-validation/DOMAIN.md"
@test "[reflection-validation] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[reflection-validation] DOMAIN presente" { [ -f "$D" ]; }
@test "[reflection-validation] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
