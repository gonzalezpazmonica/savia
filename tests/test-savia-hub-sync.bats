#!/usr/bin/env bats
# SE-376 wave1 — consolidacion savia-hub-sync
S=".claude/skills/savia-hub-sync/SKILL.md"
D=".claude/skills/savia-hub-sync/DOMAIN.md"
@test "[savia-hub-sync] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[savia-hub-sync] DOMAIN presente" { [ -f "$D" ]; }
@test "[savia-hub-sync] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
