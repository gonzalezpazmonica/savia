---
version_bump: minor
section: Added
---

### Added

- SE-489 R1: banco de evidencia de Vaults (projects/savia-vaults/eval/evidence-bench) con 302 casos en 6 categorías (A–F), esquema, validador contra ficheros en su revisión, corpus sintético inventado y validación de dificultad con el baseline híbrido (Recall@10 por categoría entre 0,50 y 0,86).

- SE-489 R1 (revisión): el split del banco queda fijo por consulta (insertar o quitar casos no mueve a los demás); el validador rechaza ids H- fuera de modo oculto, documentos no UTF-8, enlaces simbólicos fuera de la cúpula y `false` donde se exige 0; `evidence-difficulty.ts` exige `SAVIA_RAG_HOME` bajo el directorio temporal.
