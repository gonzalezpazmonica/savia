#!/usr/bin/env bats
# SE-376 wave1 — consolidacion scaling-operations
S=".claude/skills/scaling-operations/SKILL.md"
D=".claude/skills/scaling-operations/DOMAIN.md"
@test "[scaling-operations] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[scaling-operations] DOMAIN presente" { [ -f "$D" ]; }
@test "[scaling-operations] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
