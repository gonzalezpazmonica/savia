---
version_bump: minor
section: Added
---

### Added

- SE-455 y SE-456 aprobadas. Detector de tests que no pueden fallar (aserciones anuladas con «|| true» y «run» sin aserción) en el auditor de tests, con ratchet bloqueante en la CI y la regla test-evidence-criteria.md con el criterio de evidencia de REA. Reparar los primeros tests destapó que la firma de las atestaciones semanales era siempre el sha256 del fichero vacío; corregido: ahora es un checksum de integridad del cuerpo (sha256 sin clave, no prueba autoría) y la cadena enlaza con la semana anterior, no consigo misma. El ratchet compara por identidad de hallazgo, no solo por recuento.

