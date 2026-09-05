#!/usr/bin/env bats
# SE-376 wave1 — consolidacion meta-reflection
S=".claude/skills/meta-reflection/SKILL.md"
D=".claude/skills/meta-reflection/DOMAIN.md"
@test "[meta-reflection] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[meta-reflection] DOMAIN presente" { [ -f "$D" ]; }
@test "[meta-reflection] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
