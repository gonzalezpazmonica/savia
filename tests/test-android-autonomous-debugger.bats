#!/usr/bin/env bats
# SE-376 wave1 — consolidacion android-autonomous-debugger
S=".claude/skills/android-autonomous-debugger/SKILL.md"
D=".claude/skills/android-autonomous-debugger/DOMAIN.md"
@test "[android-autonomous-debugger] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[android-autonomous-debugger] DOMAIN presente" { [ -f "$D" ]; }
@test "[android-autonomous-debugger] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
