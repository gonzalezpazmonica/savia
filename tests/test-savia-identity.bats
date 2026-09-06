#!/usr/bin/env bats
# SE-376 wave2 — consolidacion aprobada savia-identity (sin borrado)
S=".claude/skills/savia-identity/SKILL.md"
D=".claude/skills/savia-identity/DOMAIN.md"
@test "[savia-identity] SKILL presente" { [ -f "$S" ]; }
@test "[savia-identity] DOMAIN consolidado" { [ -f "$D" ]; grep -qi "por qué existe" "$D"; }
@test "[savia-identity] maturity stable (SE-333 metadata.savia)" { grep -qE "savia.maturity: stable|^maturity: stable" "$S"; }
