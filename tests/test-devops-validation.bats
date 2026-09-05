#!/usr/bin/env bats
# SE-376 wave1 — consolidacion devops-validation
S=".claude/skills/devops-validation/SKILL.md"
D=".claude/skills/devops-validation/DOMAIN.md"
@test "[devops-validation] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[devops-validation] DOMAIN presente" { [ -f "$D" ]; }
@test "[devops-validation] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
