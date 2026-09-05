#!/usr/bin/env bats
# SE-376 wave1 — consolidacion company-messaging
S=".claude/skills/company-messaging/SKILL.md"
D=".claude/skills/company-messaging/DOMAIN.md"
@test "[company-messaging] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[company-messaging] DOMAIN presente" { [ -f "$D" ]; }
@test "[company-messaging] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
