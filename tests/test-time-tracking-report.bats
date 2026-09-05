#!/usr/bin/env bats
# SE-376 wave1 — consolidacion time-tracking-report
S=".claude/skills/time-tracking-report/SKILL.md"
D=".claude/skills/time-tracking-report/DOMAIN.md"
@test "[time-tracking-report] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[time-tracking-report] DOMAIN presente" { [ -f "$D" ]; }
@test "[time-tracking-report] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
