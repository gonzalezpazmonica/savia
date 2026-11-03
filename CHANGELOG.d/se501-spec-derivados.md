---
version_bump: patch
section: Added
---

### Added

- SE-501 PROPOSED (solo spec): derivados fuera de las PR. La firma de confidencialidad, el SAM y el índice/manifiesto de reglas dejan de viajar en cada PR; opción recomendada: no versionarlos y probar la auditoría de main con una ejecución de CI por commit. Incluye hallazgos verificados: la firma no prueba el escaneo, los checks de confidencialidad no son obligatorios y la clave HMAC llega a jobs de PR.

