#!/usr/bin/env bats
# SE-376 wave1 — consolidacion scheduled-messaging
S=".claude/skills/scheduled-messaging/SKILL.md"
D=".claude/skills/scheduled-messaging/DOMAIN.md"
@test "[scheduled-messaging] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[scheduled-messaging] DOMAIN presente" { [ -f "$D" ]; }
@test "[scheduled-messaging] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
