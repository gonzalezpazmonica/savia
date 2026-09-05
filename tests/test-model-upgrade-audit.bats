#!/usr/bin/env bats
# SE-376 wave1 — consolidacion model-upgrade-audit
S=".claude/skills/model-upgrade-audit/SKILL.md"
D=".claude/skills/model-upgrade-audit/DOMAIN.md"
@test "[model-upgrade-audit] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[model-upgrade-audit] DOMAIN presente" { [ -f "$D" ]; }
@test "[model-upgrade-audit] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
