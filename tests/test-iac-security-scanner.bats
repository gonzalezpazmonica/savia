#!/usr/bin/env bats
# SE-376 wave1 — consolidacion iac-security-scanner
S=".claude/skills/iac-security-scanner/SKILL.md"
D=".claude/skills/iac-security-scanner/DOMAIN.md"
@test "[iac-security-scanner] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[iac-security-scanner] DOMAIN presente" { [ -f "$D" ]; }
@test "[iac-security-scanner] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
