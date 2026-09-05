#!/usr/bin/env bats
# SE-376 wave1 — consolidacion workspace-integrity
S=".claude/skills/workspace-integrity/SKILL.md"
D=".claude/skills/workspace-integrity/DOMAIN.md"
@test "[workspace-integrity] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[workspace-integrity] DOMAIN presente" { [ -f "$D" ]; }
@test "[workspace-integrity] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
