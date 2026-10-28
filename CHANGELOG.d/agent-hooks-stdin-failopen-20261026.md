---
version_bump: patch
section: Security
---

### Security

- Seis hooks PreToolUse (lista blanca de proyectos, premerge, compliance, resumen de PR, mensaje de commit y plan-gate) estaban en fallo abierto: leían una variable que ningún runtime define. Ahora leen stdin.

