#!/usr/bin/env bats
# SE-376 wave1 — consolidacion executive-reporting
S=".claude/skills/executive-reporting/SKILL.md"
D=".claude/skills/executive-reporting/DOMAIN.md"
@test "[executive-reporting] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[executive-reporting] DOMAIN presente" { [ -f "$D" ]; }
@test "[executive-reporting] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
