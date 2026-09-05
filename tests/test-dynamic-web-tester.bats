#!/usr/bin/env bats
# SE-376 wave1 — consolidacion dynamic-web-tester
S=".claude/skills/dynamic-web-tester/SKILL.md"
D=".claude/skills/dynamic-web-tester/DOMAIN.md"
@test "[dynamic-web-tester] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[dynamic-web-tester] DOMAIN presente" { [ -f "$D" ]; }
@test "[dynamic-web-tester] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
