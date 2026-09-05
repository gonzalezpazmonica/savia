#!/usr/bin/env bats
# SE-376 wave1 — consolidacion bus-factor-analysis
S=".claude/skills/bus-factor-analysis/SKILL.md"
D=".claude/skills/bus-factor-analysis/DOMAIN.md"
@test "[bus-factor-analysis] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[bus-factor-analysis] DOMAIN presente" { [ -f "$D" ]; }
@test "[bus-factor-analysis] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
