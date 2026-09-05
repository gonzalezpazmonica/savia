#!/usr/bin/env bats
# SE-376 wave1 — consolidacion voice-inbox
S=".claude/skills/voice-inbox/SKILL.md"
D=".claude/skills/voice-inbox/DOMAIN.md"
@test "[voice-inbox] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[voice-inbox] DOMAIN presente" { [ -f "$D" ]; }
@test "[voice-inbox] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
