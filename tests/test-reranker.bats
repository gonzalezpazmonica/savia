#!/usr/bin/env bats
# SE-376 wave1 — consolidacion reranker
S=".claude/skills/reranker/SKILL.md"
D=".claude/skills/reranker/DOMAIN.md"
@test "[reranker] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[reranker] DOMAIN presente" { [ -f "$D" ]; }
@test "[reranker] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
