#!/usr/bin/env bats
# SE-376 wave1 — consolidacion context-caching
S=".claude/skills/context-caching/SKILL.md"
D=".claude/skills/context-caching/DOMAIN.md"
@test "[context-caching] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[context-caching] DOMAIN presente" { [ -f "$D" ]; }
@test "[context-caching] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
