#!/usr/bin/env bats
# SE-376 wave1 — consolidacion rbac-management
S=".claude/skills/rbac-management/SKILL.md"
D=".claude/skills/rbac-management/DOMAIN.md"
@test "[rbac-management] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[rbac-management] DOMAIN presente" { [ -f "$D" ]; }
@test "[rbac-management] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
