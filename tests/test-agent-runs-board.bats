#!/usr/bin/env bats
# SE-376 wave2 — consolidacion aprobada agent-runs-board (sin borrado)
S=".claude/skills/agent-runs-board/SKILL.md"
D=".claude/skills/agent-runs-board/DOMAIN.md"
@test "[agent-runs-board] SKILL presente" { [ -f "$S" ]; }
@test "[agent-runs-board] DOMAIN consolidado" { [ -f "$D" ]; grep -qi "por qué existe" "$D"; }
@test "[agent-runs-board] maturity stable (SE-333 metadata.savia)" { grep -qE "savia.maturity: stable|^maturity: stable" "$S"; }
