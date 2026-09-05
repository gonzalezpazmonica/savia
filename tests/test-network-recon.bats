#!/usr/bin/env bats
# SE-376 wave1 — consolidacion network-recon
S=".claude/skills/network-recon/SKILL.md"
D=".claude/skills/network-recon/DOMAIN.md"
@test "[network-recon] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[network-recon] DOMAIN presente" { [ -f "$D" ]; }
@test "[network-recon] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
