#!/usr/bin/env bats
# SE-376 wave1 — consolidacion skill-evaluation
S=".claude/skills/skill-evaluation/SKILL.md"
D=".claude/skills/skill-evaluation/DOMAIN.md"
@test "[skill-evaluation] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[skill-evaluation] DOMAIN presente" { [ -f "$D" ]; }
@test "[skill-evaluation] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
