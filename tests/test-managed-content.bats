#!/usr/bin/env bats
# SE-376 wave1 — consolidacion managed-content
S=".claude/skills/managed-content/SKILL.md"
D=".claude/skills/managed-content/DOMAIN.md"
@test "[managed-content] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[managed-content] DOMAIN presente" { [ -f "$D" ]; }
@test "[managed-content] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
