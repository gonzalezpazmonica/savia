#!/usr/bin/env bats
# SE-376 wave1 — consolidacion content-fingerprint
S=".claude/skills/content-fingerprint/SKILL.md"
D=".claude/skills/content-fingerprint/DOMAIN.md"
@test "[content-fingerprint] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[content-fingerprint] DOMAIN presente" { [ -f "$D" ]; }
@test "[content-fingerprint] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
