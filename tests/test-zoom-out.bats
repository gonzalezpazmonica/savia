#!/usr/bin/env bats
# SE-376 wave1 — consolidacion zoom-out
S=".claude/skills/zoom-out/SKILL.md"
D=".claude/skills/zoom-out/DOMAIN.md"
@test "[zoom-out] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[zoom-out] DOMAIN presente" { [ -f "$D" ]; }
@test "[zoom-out] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
