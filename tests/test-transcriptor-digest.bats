#!/usr/bin/env bats
# SE-376 wave1 — consolidacion transcriptor-digest
S=".claude/skills/transcriptor-digest/SKILL.md"
D=".claude/skills/transcriptor-digest/DOMAIN.md"
@test "[transcriptor-digest] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[transcriptor-digest] DOMAIN presente" { [ -f "$D" ]; }
@test "[transcriptor-digest] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
