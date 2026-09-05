#!/usr/bin/env bats
# SE-376 wave1 — consolidacion _template_python
S=".claude/skills/_template_python/SKILL.md"
D=".claude/skills/_template_python/DOMAIN.md"
@test "[_template_python] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[_template_python] DOMAIN presente" { [ -f "$D" ]; }
@test "[_template_python] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
