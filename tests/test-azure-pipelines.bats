#!/usr/bin/env bats
# SE-376 wave1 — consolidacion azure-pipelines
S=".claude/skills/azure-pipelines/SKILL.md"
D=".claude/skills/azure-pipelines/DOMAIN.md"
@test "[azure-pipelines] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[azure-pipelines] DOMAIN presente" { [ -f "$D" ]; }
@test "[azure-pipelines] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
