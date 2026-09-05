#!/usr/bin/env bats
# SE-376 wave1 — consolidacion mobile-security-scanner
S=".claude/skills/mobile-security-scanner/SKILL.md"
D=".claude/skills/mobile-security-scanner/DOMAIN.md"
@test "[mobile-security-scanner] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[mobile-security-scanner] DOMAIN presente" { [ -f "$D" ]; }
@test "[mobile-security-scanner] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
