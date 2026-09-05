#!/usr/bin/env bats
# SE-376 wave1 — consolidacion personal-vault
S=".claude/skills/personal-vault/SKILL.md"
D=".claude/skills/personal-vault/DOMAIN.md"
@test "[personal-vault] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[personal-vault] DOMAIN presente" { [ -f "$D" ]; }
@test "[personal-vault] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
