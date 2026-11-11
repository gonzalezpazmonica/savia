---
version_bump: minor
section: Added
---

### Added

- SE-513 S1: la cola de SE-075 admite cambios de prioridad de forma duradera (una transacción, sin duplicados, estados ADMITTED / APPLIED_TO_PLAN / UNKNOWN; APPLIED solo con prueba declarada por el agente que recibió el cambio; quien reclama el trabajo pasa a ser dueño de sus cambios abiertos, así que los recibe aunque termine antes de pedirlos y aunque el dueño anterior haya caído; en un trabajo en curso no se reordena ni se cambia el texto y la respuesta lo dice; lo que llega de CI, bots o terceros queda como contexto; un efecto sigue pendiente de su permiso). Subórdenes admit, pull, ack y changes en scripts/lib/task-queue.py.

