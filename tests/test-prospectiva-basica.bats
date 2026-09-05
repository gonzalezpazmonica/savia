#!/usr/bin/env bats
# SE-376 wave1 — consolidacion prospectiva-basica
S=".claude/skills/prospectiva-basica/SKILL.md"
D=".claude/skills/prospectiva-basica/DOMAIN.md"
@test "[prospectiva-basica] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[prospectiva-basica] DOMAIN presente" { [ -f "$D" ]; }
@test "[prospectiva-basica] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
