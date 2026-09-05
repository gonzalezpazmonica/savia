#!/usr/bin/env bats
# SE-376 wave1 — consolidacion tier3-probes
S=".claude/skills/tier3-probes/SKILL.md"
D=".claude/skills/tier3-probes/DOMAIN.md"
@test "[tier3-probes] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[tier3-probes] DOMAIN presente" { [ -f "$D" ]; }
@test "[tier3-probes] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
