#!/usr/bin/env bats
# SE-376 wave1 — consolidacion robotica-diseno
S=".claude/skills/robotica-diseno/SKILL.md"
D=".claude/skills/robotica-diseno/DOMAIN.md"
@test "[robotica-diseno] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[robotica-diseno] DOMAIN presente" { [ -f "$D" ]; }
@test "[robotica-diseno] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
