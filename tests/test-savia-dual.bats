#!/usr/bin/env bats
# SE-376 wave1 — consolidacion savia-dual
S=".claude/skills/savia-dual/SKILL.md"
D=".claude/skills/savia-dual/DOMAIN.md"
@test "[savia-dual] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[savia-dual] DOMAIN presente" { [ -f "$D" ]; }
@test "[savia-dual] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
