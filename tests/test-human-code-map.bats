#!/usr/bin/env bats
# SE-376 wave1 — consolidacion human-code-map
S=".claude/skills/human-code-map/SKILL.md"
D=".claude/skills/human-code-map/DOMAIN.md"
@test "[human-code-map] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[human-code-map] DOMAIN presente" { [ -f "$D" ]; }
@test "[human-code-map] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
