#!/usr/bin/env bats
# SE-376 wave1 — consolidacion design-an-interface
S=".claude/skills/design-an-interface/SKILL.md"
D=".claude/skills/design-an-interface/DOMAIN.md"
@test "[design-an-interface] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[design-an-interface] DOMAIN presente" { [ -f "$D" ]; }
@test "[design-an-interface] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
