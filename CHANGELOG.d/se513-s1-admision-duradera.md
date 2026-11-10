---
version_bump: minor
section: Added
---

### Added

- SE-513 S1: la cola de SE-075 admite cambios de prioridad de forma duradera (una transacción, sin duplicados, estados ADMITTED / APPLIED_TO_PLAN / UNKNOWN; APPLIED solo con prueba del plan del agente; lo que llega de CI, bots o terceros queda como contexto; un efecto sigue pendiente de su permiso). Subórdenes admit, pull, ack y changes en scripts/lib/task-queue.py.

