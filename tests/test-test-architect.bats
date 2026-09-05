#!/usr/bin/env bats
# SE-376 wave1 — consolidacion test-architect
S=".claude/skills/test-architect/SKILL.md"
D=".claude/skills/test-architect/DOMAIN.md"
@test "[test-architect] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[test-architect] DOMAIN presente" { [ -f "$D" ]; }
@test "[test-architect] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
