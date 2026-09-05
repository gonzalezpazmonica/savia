#!/usr/bin/env bats
# SE-376 wave1 — consolidacion sovereignty-auditor
S=".claude/skills/sovereignty-auditor/SKILL.md"
D=".claude/skills/sovereignty-auditor/DOMAIN.md"
@test "[sovereignty-auditor] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[sovereignty-auditor] DOMAIN presente" { [ -f "$D" ]; }
@test "[sovereignty-auditor] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
