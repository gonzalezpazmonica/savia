#!/usr/bin/env bats
# SE-376 wave1 — consolidacion org-stakeholder-mapper
S=".claude/skills/org-stakeholder-mapper/SKILL.md"
D=".claude/skills/org-stakeholder-mapper/DOMAIN.md"
@test "[org-stakeholder-mapper] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[org-stakeholder-mapper] DOMAIN presente" { [ -f "$D" ]; }
@test "[org-stakeholder-mapper] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
