#!/usr/bin/env bats
# SE-376 wave1 — consolidacion _template
S=".claude/skills/_template/SKILL.md"
D=".claude/skills/_template/DOMAIN.md"
@test "[_template] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[_template] DOMAIN presente" { [ -f "$D" ]; }
@test "[_template] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
