#!/usr/bin/env bats
# SE-376 wave1 — consolidacion tls-security-checker
S=".claude/skills/tls-security-checker/SKILL.md"
D=".claude/skills/tls-security-checker/DOMAIN.md"
@test "[tls-security-checker] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[tls-security-checker] DOMAIN presente" { [ -f "$D" ]; }
@test "[tls-security-checker] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
