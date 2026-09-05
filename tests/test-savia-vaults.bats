#!/usr/bin/env bats
# SE-376 wave1 — consolidacion savia-vaults
S=".claude/skills/savia-vaults/SKILL.md"
D=".claude/skills/savia-vaults/DOMAIN.md"
@test "[savia-vaults] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[savia-vaults] DOMAIN presente" { [ -f "$D" ]; }
@test "[savia-vaults] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
