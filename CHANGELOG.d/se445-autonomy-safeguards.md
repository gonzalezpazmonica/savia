---
version_bump: minor
section: Added
---

### Added

- SE-445 salvaguardas de ejecución autónoma. S1: `repeat-tool-guard.sh` bloquea la 3.ª llamada idéntica (PreToolUse, exit 2) en ramas `agent/*` o con `SAVIA_AUTONOMOUS_RUN=1`, con recordatorio en la 2.ª y Handback en el mensaje. S2: `turn-budget-inject.sh` muestra turnos usados y minutos restantes del time-box (opt-in, `SAVIA_TURN_BUDGET=on`). S3: `action-review.sh` y `action-review-policy.md`, revisor de acciones Bash con doble opt-in, fail-closed en tiers 3 y 4. S4: `--success-check` y `--max-retries` (máx. 3) en `savia-automations.sh`; el reintento recibe el fallo del check y una entrada idéntica se rechaza. Corre igual en OpenCode a través del registro de `savia-gates` (test de paridad incluido).
