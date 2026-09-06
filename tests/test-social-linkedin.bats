#!/usr/bin/env bats
# SE-376 wave2 — consolidacion aprobada social-linkedin (sin borrado)
S=".claude/skills/social-linkedin/SKILL.md"
D=".claude/skills/social-linkedin/DOMAIN.md"
@test "[social-linkedin] SKILL presente" { [ -f "$S" ]; }
@test "[social-linkedin] DOMAIN consolidado" { [ -f "$D" ]; grep -qi "por qué existe" "$D"; }
@test "[social-linkedin] maturity stable (SE-333 metadata.savia)" { grep -qE "savia.maturity: stable|^maturity: stable" "$S"; }
