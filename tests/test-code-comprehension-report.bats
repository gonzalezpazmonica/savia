#!/usr/bin/env bats
# SE-376 wave1 — consolidacion code-comprehension-report
S=".claude/skills/code-comprehension-report/SKILL.md"
D=".claude/skills/code-comprehension-report/DOMAIN.md"
@test "[code-comprehension-report] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[code-comprehension-report] DOMAIN presente" { [ -f "$D" ]; }
@test "[code-comprehension-report] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
