#!/usr/bin/env bats
# SE-376 wave1 — consolidacion agent-messaging
S=".claude/skills/agent-messaging/SKILL.md"
D=".claude/skills/agent-messaging/DOMAIN.md"
@test "[agent-messaging] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[agent-messaging] DOMAIN presente" { [ -f "$D" ]; }
@test "[agent-messaging] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
