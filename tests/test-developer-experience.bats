#!/usr/bin/env bats
# SE-376 wave1 — consolidacion developer-experience
S=".claude/skills/developer-experience/SKILL.md"
D=".claude/skills/developer-experience/DOMAIN.md"
@test "[developer-experience] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[developer-experience] DOMAIN presente" { [ -f "$D" ]; }
@test "[developer-experience] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
