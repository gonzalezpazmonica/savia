---
version_bump: patch
section: Removed
---

### Removed

- Poda lote 3: 38 programas de specs hechas de junio a septiembre sin consumidor (memoria temporal, grafo de conocimiento, informes, auditorías, agentes y utilidades sueltas) y sus pruebas; se quita el bloque de línea de tiempo de spec-lifecycle.sh. Recuperables desde el historial. La selección dinámica de BATS (`ci-bats-deps.sh`, `.deps-rules.yaml`) deja de citar los dos tests borrados y un test nuevo exige que todo test del núcleo y de las reglas por directorio exista.
