---
version_bump: patch
section: Added
---

### Added

- SE-494 (PROPOSED): spec de trazas a regresiones herméticas que extiende SE-364 — esquema savia.trace/v1, 10 fallos congelados con invariantes y fail-to-pass, gate en CI y OTLP opcional; documenta 7 hallazgos verificados en el bucle de evidencia (to_evals emite casos open, nivel ausente tratado como N1, paired-delta en verde con cero pares).
- Test de contrato de la spec SE-494 en `tests/bats/` (lo ejecuta el CI de PR): cada decisión de diseño se comprueba contra la spec y contra una copia mutada que debe fallar.
