#!/usr/bin/env bats
# SE-376 wave1 — consolidacion product-discovery
S=".claude/skills/product-discovery/SKILL.md"
D=".claude/skills/product-discovery/DOMAIN.md"
@test "[product-discovery] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[product-discovery] DOMAIN presente" { [ -f "$D" ]; }
@test "[product-discovery] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
