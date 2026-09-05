#!/usr/bin/env bats
# SE-376 wave1 — consolidacion parallel-dispatch
S=".claude/skills/parallel-dispatch/SKILL.md"
D=".claude/skills/parallel-dispatch/DOMAIN.md"
@test "[parallel-dispatch] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[parallel-dispatch] DOMAIN presente" { [ -f "$D" ]; }
@test "[parallel-dispatch] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
