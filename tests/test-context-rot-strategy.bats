#!/usr/bin/env bats
# SE-376 wave1 — consolidacion context-rot-strategy
S=".claude/skills/context-rot-strategy/SKILL.md"
D=".claude/skills/context-rot-strategy/DOMAIN.md"
@test "[context-rot-strategy] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[context-rot-strategy] DOMAIN presente" { [ -f "$D" ]; }
@test "[context-rot-strategy] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
