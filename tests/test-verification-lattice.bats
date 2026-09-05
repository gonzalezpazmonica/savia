#!/usr/bin/env bats
# SE-376 wave1 — consolidacion verification-lattice
S=".claude/skills/verification-lattice/SKILL.md"
D=".claude/skills/verification-lattice/DOMAIN.md"
@test "[verification-lattice] SKILL sustancial" { [ -f "$S" ]; [ "$(wc -l < "$S")" -ge 50 ]; }
@test "[verification-lattice] DOMAIN presente" { [ -f "$D" ]; }
@test "[verification-lattice] maturity stable" { grep -qE "^(savia\.)?maturity: stable" "$S"; }
