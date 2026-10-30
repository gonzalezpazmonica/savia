---
version_bump: minor
section: Added
---

### Added

- SE-489 (base): contrato RetrievalRoute, guard de recuperación centralizado (cúpula, nivel de nota y cuarentena, ACL de Files, borrado y reclasificación) y runner con guard final de procedencia.
- SE-489: M0 adapta el híbrido actual al contrato sin cambiar su resultado; vault_rag acepta route, budget, seed y asOf opt-in (sin route, comportamiento de main).
- SE-489: rag eval --route/--bench con EvidenceRecall, exact-identifier-hit, lecturas no autorizadas, revisiones prohibidas, abstención correcta, p50/p95, RSS e IC 95 % por bootstrap pareado.
- SE-489: batería negativa de seguridad reutilizable por ruta (tests/retrieval/security-battery.ts) y guía docs/retrieval-routes.md.

