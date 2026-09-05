#!/usr/bin/env bats
# SE-376 wave1 — consolidacion agent-file-map
S=".claude/skills/agent-file-map/SKILL.md"
D=".claude/skills/agent-file-map/DOMAIN.md"
@test "[agent-file-map] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[agent-file-map] DOMAIN presente" { [ -f "$D" ]; }
@test "[agent-file-map] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
