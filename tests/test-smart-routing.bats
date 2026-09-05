#!/usr/bin/env bats
# SE-376 wave1 — consolidacion smart-routing
S=".claude/skills/smart-routing/SKILL.md"
D=".claude/skills/smart-routing/DOMAIN.md"
@test "[smart-routing] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[smart-routing] DOMAIN presente" { [ -f "$D" ]; }
@test "[smart-routing] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
