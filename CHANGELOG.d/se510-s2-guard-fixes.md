---
version_bump: minor
section: Fixed
---

### Fixed

- SE-510 S2: gh pr create desde un worktree mira el .pr-summary.md de ese árbol (resolvedor scripts/lib/pr_summary_root.py; el gate lo coloca la operadora) y anuncia el encabezado exigido con plantilla docs/templates/pr-summary.md y aviso en pr-plan.
- SE-510 S2: paridad de veredictos bash/TS sobre el corpus (guard-corpus --ts, exit 4 si difieren) y cierre del hueco TS que dejaba pasar un add o un commit con destino no resoluble.
- SE-510 S2: registro local de bloqueos con tasa de falsos positivos (scripts/guard-blocks.sh record|mark|report|wrap, HMAC con clave local, sin la orden en claro); los guards TS ya registran.

