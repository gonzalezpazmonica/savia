---
version_bump: patch
section: Security
---

### Security

- Los hooks de subagentes (recursión, trabajos protegidos, validación de delegación y posprocesado) se registran también para «Agent», el nombre actual de la herramienta; con solo «Task» no se ejecutaban.
- `protected-job-guard` trata también `SAVIA_LOOP_CONTEXT` (lo exportan `overnight-sprint-loop.sh` y `recursion-guard-export.sh`) como contexto autónomo: dentro de un bucle, los agentes protegidos se bloquean salvo override explícito.

