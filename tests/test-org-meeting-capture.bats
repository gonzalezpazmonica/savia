#!/usr/bin/env bats
# SE-376 wave1 — consolidacion org-meeting-capture
S=".claude/skills/org-meeting-capture/SKILL.md"
D=".claude/skills/org-meeting-capture/DOMAIN.md"
@test "[org-meeting-capture] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[org-meeting-capture] DOMAIN presente" { [ -f "$D" ]; }
@test "[org-meeting-capture] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
