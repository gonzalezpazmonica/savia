#!/usr/bin/env bats
# SE-376 wave1 — consolidacion automation-scheduler
S=".claude/skills/automation-scheduler/SKILL.md"
D=".claude/skills/automation-scheduler/DOMAIN.md"
@test "[automation-scheduler] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[automation-scheduler] DOMAIN presente" { [ -f "$D" ]; }
@test "[automation-scheduler] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
