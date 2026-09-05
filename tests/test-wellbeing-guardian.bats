#!/usr/bin/env bats
# SE-376 wave1 — consolidacion wellbeing-guardian
S=".claude/skills/wellbeing-guardian/SKILL.md"
D=".claude/skills/wellbeing-guardian/DOMAIN.md"
@test "[wellbeing-guardian] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[wellbeing-guardian] DOMAIN presente" { [ -f "$D" ]; }
@test "[wellbeing-guardian] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
