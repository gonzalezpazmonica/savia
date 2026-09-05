#!/usr/bin/env bats
# SE-376 wave1 — consolidacion savia-labs
S=".claude/skills/savia-labs/SKILL.md"
D=".claude/skills/savia-labs/DOMAIN.md"
@test "[savia-labs] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[savia-labs] DOMAIN presente" { [ -f "$D" ]; }
@test "[savia-labs] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
