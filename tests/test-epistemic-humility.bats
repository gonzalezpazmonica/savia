#!/usr/bin/env bats
# SE-376 wave1 — consolidacion epistemic-humility
S=".claude/skills/epistemic-humility/SKILL.md"
D=".claude/skills/epistemic-humility/DOMAIN.md"
@test "[epistemic-humility] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[epistemic-humility] DOMAIN presente" { [ -f "$D" ]; }
@test "[epistemic-humility] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
