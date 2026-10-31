---
version_bump: minor
section: Added
---

### Added

- SE-489 M2: ruta de recuperación con reranker cross-encoder local (ONNX, fijado por digest, sin red) sobre el top-N de M0; fail-open en calidad al orden de M0 con aviso y traza; latencia del reranker medida aparte; informe de medición en projects/savia-vaults/docs/audits.

- SE-489 M2 (revisión): la ruta recorta a `k` hits con y sin reranker; el modelo y el tokenizador se leen una sola vez (hash y carga sobre la misma copia); el fallo de carga se recuerda 60 s; el plazo del reranker se comprueba también tras cada lote; la traza usa motivos propios sin rutas ni detalle de librerías; registros de medición acotados; la consulta se acota a 1024 caracteres; `--limit` y `--per-category` rechazan 0 y valores no numéricos.
