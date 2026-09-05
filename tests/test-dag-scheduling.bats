#!/usr/bin/env bats
# SE-376 wave1 — consolidacion dag-scheduling
S=".claude/skills/dag-scheduling/SKILL.md"
D=".claude/skills/dag-scheduling/DOMAIN.md"
@test "[dag-scheduling] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[dag-scheduling] DOMAIN presente" { [ -f "$D" ]; }
@test "[dag-scheduling] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
