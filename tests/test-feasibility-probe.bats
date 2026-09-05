#!/usr/bin/env bats
# SE-376 wave1 — consolidacion feasibility-probe
S=".claude/skills/feasibility-probe/SKILL.md"
D=".claude/skills/feasibility-probe/DOMAIN.md"
@test "[feasibility-probe] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[feasibility-probe] DOMAIN presente" { [ -f "$D" ]; }
@test "[feasibility-probe] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
