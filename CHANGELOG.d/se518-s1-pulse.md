---
version_bump: minor
section: Added
---

### Added

- SE-518 S1: proyecto Pulse (projects/pulse, Python estándar sin dependencias). Contratos con esquema y validador (eventos, peticiones, latido, presencia, acuses), lanzador `pulse run` que emite inicio, latido y fin con código y clase, `pulse status` en llano y canal de respaldo (`pulse deliver`, `pulse inbox`). Fail-closed: ficheros ajenos o escribibles por otros son FALLIDA, latido vencido es «sin señales». No incluye planificador, freno ni servicio (S2–S7).

- SE-518 S1 (revisión): `pulse deliver` notifica fuera del cerrojo de escritor y no avisa dos veces con pasadas simultáneas; el fin de un trabajo y su petición se anotan juntos (y el reintento regenera la que falte); fechas imposibles, NaN y JSON muy anidado son FALLIDA; un dato fuera de contrato sale con 2.

- SE-518 S1 (segunda revisión): con el ledger ilegible `pulse deliver` no notifica y sale con 1 (antes avisaba y repetía el aviso en cada pasada); otra pasada en curso sale con 0; una presencia que vence antes de su fecha no cuenta; los esquemas se comprueban enteros al cargar; `pulse run` da la orden de reparación si no pudo anotar el fin y no duplica el Ctrl-C de la terminal; `inbox` no pasa secuencias de control a la terminal.
