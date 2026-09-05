#!/usr/bin/env bats
# SE-376 wave1 — consolidacion obscura-browser
S=".claude/skills/obscura-browser/SKILL.md"
D=".claude/skills/obscura-browser/DOMAIN.md"
@test "[obscura-browser] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[obscura-browser] DOMAIN presente" { [ -f "$D" ]; }
@test "[obscura-browser] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
