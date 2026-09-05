#!/usr/bin/env bats
# SE-376 wave2 — consolidacion aprobada weekly-report (sin borrado)
S=".claude/skills/weekly-report/SKILL.md"
D=".claude/skills/weekly-report/DOMAIN.md"
@test "[weekly-report] SKILL presente" { [ -f "$S" ]; }
@test "[weekly-report] DOMAIN consolidado" { [ -f "$D" ]; grep -qi "por qué existe" "$D"; }
@test "[weekly-report] maturity stable (SE-333 metadata.savia)" { grep -qE "savia.maturity: stable|^maturity: stable" "$S"; }
