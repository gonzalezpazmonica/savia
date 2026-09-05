#!/usr/bin/env bats
# SE-376 wave1 — consolidacion azure-devops-queries
S=".claude/skills/azure-devops-queries/SKILL.md"
D=".claude/skills/azure-devops-queries/DOMAIN.md"
@test "[azure-devops-queries] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[azure-devops-queries] DOMAIN presente" { [ -f "$D" ]; }
@test "[azure-devops-queries] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
