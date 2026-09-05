#!/usr/bin/env bats
# SE-376 wave1 — consolidacion nuclei-scanning
S=".claude/skills/nuclei-scanning/SKILL.md"
D=".claude/skills/nuclei-scanning/DOMAIN.md"
@test "[nuclei-scanning] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[nuclei-scanning] DOMAIN presente" { [ -f "$D" ]; }
@test "[nuclei-scanning] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
