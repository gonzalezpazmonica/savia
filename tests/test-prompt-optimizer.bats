#!/usr/bin/env bats
# SE-376 wave1 — consolidacion prompt-optimizer
S=".claude/skills/prompt-optimizer/SKILL.md"
D=".claude/skills/prompt-optimizer/DOMAIN.md"
@test "[prompt-optimizer] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[prompt-optimizer] DOMAIN presente" { [ -f "$D" ]; }
@test "[prompt-optimizer] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
