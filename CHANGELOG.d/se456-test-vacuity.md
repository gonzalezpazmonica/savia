---
version_bump: minor
section: Added
---

### Added

- SE-455 y SE-456 aprobadas. Detector de tests que no pueden fallar (aserciones anuladas con «|| true» y «run» sin aserción) en el auditor de tests, con ratchet bloqueante en la CI y la regla test-evidence-criteria.md con el criterio de evidencia de REA. Reparar los primeros tests destapó que la firma de las atestaciones semanales era siempre el sha256 del fichero vacío; corregido: ahora es un checksum de integridad del cuerpo (sha256 sin clave, no prueba autoría) y la cadena enlaza con la semana anterior, no consigo misma. El ratchet compara por identidad de hallazgo, no solo por recuento. Tras la revisión independiente: `test-auditor.sh` certifica y sale con 0 solo si el fichero no tiene vacuidad (antes lo decidía la puntuación sola); el ratchet falla cerrado sin fichero de identidades; el detector también marca aserciones encadenadas con «&&» anuladas, «|| /ruta/true» e «if … then :; fi», no da por comprobado un «echo $output» y escanea «@test» con comentario tras la llave; `savia-attest.sh` valida el formato de semana y acepta `--week`. Un test de topic-cluster que no comprobaba nada ahora comprueba que salen 2 temas.
