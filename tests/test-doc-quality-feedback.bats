#!/usr/bin/env bats
# SE-376 wave1 — consolidacion doc-quality-feedback
S=".claude/skills/doc-quality-feedback/SKILL.md"
D=".claude/skills/doc-quality-feedback/DOMAIN.md"
@test "[doc-quality-feedback] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[doc-quality-feedback] DOMAIN presente" { [ -f "$D" ]; }
@test "[doc-quality-feedback] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
