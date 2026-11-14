---
version_bump: minor
section: Added
---

### Added

- SE-518 S1: proyecto Pulse (projects/pulse, Python estándar sin dependencias). Contratos con esquema y validador (eventos, peticiones, latido, presencia, acuses), lanzador `pulse run` que emite inicio, latido y fin con código y clase, `pulse status` en llano y canal de respaldo (`pulse deliver`, `pulse inbox`). Fail-closed: ficheros ajenos o escribibles por otros son FALLIDA, latido vencido es «sin señales». No incluye planificador, freno ni servicio (S2–S7).

