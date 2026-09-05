#!/usr/bin/env bats
# SE-376 wave1 — consolidacion smart-calendar
S=".claude/skills/smart-calendar/SKILL.md"
D=".claude/skills/smart-calendar/DOMAIN.md"
@test "[smart-calendar] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[smart-calendar] DOMAIN presente" { [ -f "$D" ]; }
@test "[smart-calendar] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
