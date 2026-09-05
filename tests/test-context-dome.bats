#!/usr/bin/env bats
# SE-376 wave1 — consolidacion context-dome
S=".claude/skills/context-dome/SKILL.md"
D=".claude/skills/context-dome/DOMAIN.md"
@test "[context-dome] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[context-dome] DOMAIN presente" { [ -f "$D" ]; }
@test "[context-dome] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
