#!/usr/bin/env bats
# SE-376 wave1 — consolidacion resource-references
S=".claude/skills/resource-references/SKILL.md"
D=".claude/skills/resource-references/DOMAIN.md"
@test "[resource-references] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[resource-references] DOMAIN presente" { [ -f "$D" ]; }
@test "[resource-references] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
