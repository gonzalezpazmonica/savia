#!/usr/bin/env bats
# SE-376 wave1 — consolidacion org-registrar
S=".claude/skills/org-registrar/SKILL.md"
D=".claude/skills/org-registrar/DOMAIN.md"
@test "[org-registrar] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[org-registrar] DOMAIN presente" { [ -f "$D" ]; }
@test "[org-registrar] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
