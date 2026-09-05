#!/usr/bin/env bats
# SE-376 wave1 — consolidacion context-optimized-dev
S=".claude/skills/context-optimized-dev/SKILL.md"
D=".claude/skills/context-optimized-dev/DOMAIN.md"
@test "[context-optimized-dev] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[context-optimized-dev] DOMAIN presente" { [ -f "$D" ]; }
@test "[context-optimized-dev] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
