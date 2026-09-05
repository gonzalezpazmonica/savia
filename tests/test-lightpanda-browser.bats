#!/usr/bin/env bats
# SE-376 wave1 — consolidacion lightpanda-browser
S=".claude/skills/lightpanda-browser/SKILL.md"
D=".claude/skills/lightpanda-browser/DOMAIN.md"
@test "[lightpanda-browser] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[lightpanda-browser] DOMAIN presente" { [ -f "$D" ]; }
@test "[lightpanda-browser] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
