#!/usr/bin/env bats
# SE-376 wave1 — consolidacion emergency-mode
S=".claude/skills/emergency-mode/SKILL.md"
D=".claude/skills/emergency-mode/DOMAIN.md"
@test "[emergency-mode] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[emergency-mode] DOMAIN presente" { [ -f "$D" ]; }
@test "[emergency-mode] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
