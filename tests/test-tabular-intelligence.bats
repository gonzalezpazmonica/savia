#!/usr/bin/env bats
# SE-376 wave2 — consolidacion aprobada tabular-intelligence (sin borrado)
S=".claude/skills/tabular-intelligence/SKILL.md"
D=".claude/skills/tabular-intelligence/DOMAIN.md"
@test "[tabular-intelligence] SKILL presente" { [ -f "$S" ]; }
@test "[tabular-intelligence] DOMAIN consolidado" { [ -f "$D" ]; grep -qi "por qué existe" "$D"; }
@test "[tabular-intelligence] maturity stable (SE-333 metadata.savia)" { grep -qE "savia.maturity: stable|^maturity: stable" "$S"; }
