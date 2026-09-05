#!/usr/bin/env bats
# SE-376 wave1 — consolidacion ai-labor-impact
S=".claude/skills/ai-labor-impact/SKILL.md"
D=".claude/skills/ai-labor-impact/DOMAIN.md"
@test "[ai-labor-impact] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[ai-labor-impact] DOMAIN presente" { [ -f "$D" ]; }
@test "[ai-labor-impact] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
