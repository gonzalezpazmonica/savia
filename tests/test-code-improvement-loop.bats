#!/usr/bin/env bats
# SE-376 wave1 — consolidacion code-improvement-loop
S=".claude/skills/code-improvement-loop/SKILL.md"
D=".claude/skills/code-improvement-loop/DOMAIN.md"
@test "[code-improvement-loop] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[code-improvement-loop] DOMAIN presente" { [ -f "$D" ]; }
@test "[code-improvement-loop] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
