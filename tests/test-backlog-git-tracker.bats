#!/usr/bin/env bats
# SE-376 wave1 — consolidacion backlog-git-tracker
S=".claude/skills/backlog-git-tracker/SKILL.md"
D=".claude/skills/backlog-git-tracker/DOMAIN.md"
@test "[backlog-git-tracker] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[backlog-git-tracker] DOMAIN presente" { [ -f "$D" ]; }
@test "[backlog-git-tracker] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
