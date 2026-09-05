#!/usr/bin/env bats
# SE-376 wave1 — consolidacion banking-architecture
S=".claude/skills/banking-architecture/SKILL.md"
D=".claude/skills/banking-architecture/DOMAIN.md"
@test "[banking-architecture] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[banking-architecture] DOMAIN presente" { [ -f "$D" ]; }
@test "[banking-architecture] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
