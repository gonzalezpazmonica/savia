#!/usr/bin/env bats
# SE-376 wave1 — consolidacion context-interview-conductor
S=".claude/skills/context-interview-conductor/SKILL.md"
D=".claude/skills/context-interview-conductor/DOMAIN.md"
@test "[context-interview-conductor] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[context-interview-conductor] DOMAIN presente" { [ -f "$D" ]; }
@test "[context-interview-conductor] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
