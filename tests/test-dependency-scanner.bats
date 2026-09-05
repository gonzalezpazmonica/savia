#!/usr/bin/env bats
# SE-376 wave1 — consolidacion dependency-scanner
S=".claude/skills/dependency-scanner/SKILL.md"
D=".claude/skills/dependency-scanner/DOMAIN.md"
@test "[dependency-scanner] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[dependency-scanner] DOMAIN presente" { [ -f "$D" ]; }
@test "[dependency-scanner] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
