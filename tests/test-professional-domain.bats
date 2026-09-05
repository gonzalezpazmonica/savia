#!/usr/bin/env bats
# SE-376 wave2 — consolidacion aprobada professional-domain (sin borrado)
S=".claude/skills/professional-domain/SKILL.md"
D=".claude/skills/professional-domain/DOMAIN.md"
@test "[professional-domain] SKILL presente" { [ -f "$S" ]; }
@test "[professional-domain] DOMAIN consolidado" { [ -f "$D" ]; grep -qi "por qué existe" "$D"; }
@test "[professional-domain] maturity stable (SE-333 metadata.savia)" { grep -qE "savia.maturity: stable|^maturity: stable" "$S"; }
