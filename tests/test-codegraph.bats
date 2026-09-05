#!/usr/bin/env bats
# SE-376 wave1 — consolidacion codegraph
S=".claude/skills/codegraph/SKILL.md"
D=".claude/skills/codegraph/DOMAIN.md"
@test "[codegraph] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[codegraph] DOMAIN presente" { [ -f "$D" ]; }
@test "[codegraph] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
