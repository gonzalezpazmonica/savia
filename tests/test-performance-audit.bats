#!/usr/bin/env bats
# SE-376 wave1 — consolidacion performance-audit
S=".claude/skills/performance-audit/SKILL.md"
D=".claude/skills/performance-audit/DOMAIN.md"
@test "[performance-audit] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[performance-audit] DOMAIN presente" { [ -f "$D" ]; }
@test "[performance-audit] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
