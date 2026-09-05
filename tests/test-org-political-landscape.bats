#!/usr/bin/env bats
# SE-376 wave1 — consolidacion org-political-landscape
S=".claude/skills/org-political-landscape/SKILL.md"
D=".claude/skills/org-political-landscape/DOMAIN.md"
@test "[org-political-landscape] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[org-political-landscape] DOMAIN presente" { [ -f "$D" ]; }
@test "[org-political-landscape] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
