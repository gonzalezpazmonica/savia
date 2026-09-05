#!/usr/bin/env bats
# SE-376 wave1 — consolidacion savia-memory
S=".claude/skills/savia-memory/SKILL.md"
D=".claude/skills/savia-memory/DOMAIN.md"
@test "[savia-memory] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[savia-memory] DOMAIN presente" { [ -f "$D" ]; }
@test "[savia-memory] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
