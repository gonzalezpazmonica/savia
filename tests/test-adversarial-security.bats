#!/usr/bin/env bats
# SE-376 wave1 — consolidacion adversarial-security
S=".claude/skills/adversarial-security/SKILL.md"
D=".claude/skills/adversarial-security/DOMAIN.md"
@test "[adversarial-security] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[adversarial-security] DOMAIN presente" { [ -f "$D" ]; }
@test "[adversarial-security] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
