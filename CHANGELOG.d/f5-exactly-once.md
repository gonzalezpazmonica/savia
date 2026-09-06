---
version_bump: patch
section: Fixed
---
- **SE-387 F5 exactly-once v2**: f5-state.sh (reserved→submitted→closed; close exige PR MERGED real; submitted reanudable; retry tras closed→ALREADY_EXECUTED), push-pr integrado (reservation tras grant+risk-tier, PENDING/SUBMITTED explícito), judge-routing completa 5 jueces Coherence Court, benchmark --execute con evidencia de sesiones reales. Tests f5-cases/f5-exactly-once/f5-close-guard.
