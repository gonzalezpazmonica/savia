#!/usr/bin/env bats
# SE-376 wave1 — consolidacion client-profile-manager
S=".claude/skills/client-profile-manager/SKILL.md"
D=".claude/skills/client-profile-manager/DOMAIN.md"
@test "[client-profile-manager] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[client-profile-manager] DOMAIN presente" { [ -f "$D" ]; }
@test "[client-profile-manager] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
