#!/usr/bin/env bats
# SE-376 wave1 — consolidacion meeting-transcript-extract
S=".claude/skills/meeting-transcript-extract/SKILL.md"
D=".claude/skills/meeting-transcript-extract/DOMAIN.md"
@test "[meeting-transcript-extract] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[meeting-transcript-extract] DOMAIN presente" { [ -f "$D" ]; }
@test "[meeting-transcript-extract] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
