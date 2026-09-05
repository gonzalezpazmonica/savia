#!/usr/bin/env bats
# SE-376 wave1 — consolidacion rules-traceability
S=".claude/skills/rules-traceability/SKILL.md"
D=".claude/skills/rules-traceability/DOMAIN.md"
@test "[rules-traceability] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[rules-traceability] DOMAIN presente" { [ -f "$D" ]; }
@test "[rules-traceability] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
