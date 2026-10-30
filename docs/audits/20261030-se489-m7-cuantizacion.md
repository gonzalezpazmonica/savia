# SE-489 M7 — Cuantización en sombra: medición sobre savia-docs y a escala sintética

Fecha: 2026-10-30. Rama `agent/se489-m7-20261023`. Datos crudos: `docs/audits/20261030-se489-m7-datos/`.
Reproducción: `projects/savia-vaults/scripts/bench-quantization.ts` (`real` y `synth`).

## Conclusión

1. **En savia-docs compensa poco.** Con 10 796 chunks el float32 pesa 44 MB y una búsqueda exacta tarda 41 ms (p50). Embeber la consulta tarda 156 ms (p50): la búsqueda es ~20 % de la latencia. Binario + rescoring (M=100) baja la búsqueda a 3,5–4,2 ms; el ahorro (~37 ms) es perceptible solo en el límite.
2. **Recall perdido en savia-docs, dense-only, 36 consultas:**
   - Binario + rescoring float32: **0 pp** en Recall@10 y MRR frente al float32 exacto, para M = 50, 100, 200 y 400 (0,736 / 0,561 en todos).
   - A nivel de chunk, el solape del top-10 con el exacto es 0,964 (M=50), 0,986 (M=100), 0,997 (M=200), 1,000 (M=400). M=100 pierde 1,4 pp de chunks, y ninguno cambia la lista de documentos.
   - Binario puro sin rescoring: solape 0,628, MRR 0,503 (−0,058). No usar.
   - int8: solape 0,997, mismo Recall@10 y MRR. Pierde 0,3 pp, pero en JS es más lento que el float32.
3. **Umbral de tamaño.**
   - Latencia: la búsqueda exacta cuesta ~2–4 µs por vector (1024 dims, JS; 23 ms y 41 ms por 10,8 k en dos ejecuciones). Pasa de 100 ms hacia **~25 000–50 000 vectores**; con 100 000 son 413 ms frente a 18 ms binario (23×); con 1 M, 4,2 s frente a 0,17 s (25×). El presupuesto de 100 ms es supuesto mío, no una cifra de la spec.
   - Memoria: la proyección binaria con rescoring desde disco evita tener el float32 residente (4 GB a 1 M vectores; ~250 MB de pico en la medición sintética). **Solo si además los chunks dejan de cargarse en RAM** (ver «Hallazgos»). Con el índice actual, el ahorro de RAM a 1 M sería falso.
   - Sugerencia: no activar por debajo de ~50 000 vectores. Entre 50 000 y 250 000 es opt-in por latencia. Por encima de ~250 000 (≥ 1 GB de float32) hace falta, y solo con chunks diferidos.
4. **Disco.** La proyección añade almacenamiento, no lo ahorra: el float32 sigue siendo la fuente de verdad. Binario +3 % (1,4 MB sobre 44 MB), int8 +25 %.

## Qué se construyó

| Módulo | Contenido |
|---|---|
| `quantize.ts` | Signo con bitpacking (MSB primero, NaN/0/−0 → 0, relleno 0) e int8 por dimensión con percentil 99,9 sobre muestra determinista. |
| `binary-store.ts` | Proyecciones por generación, con `binding` sha256 sobre generación, seq, modelo y digest, dims, nº y orden/contenido/clasificación de chunks, clasificación y versión del cuantizador. Mismo cifrado que la fuente. Ficheros 0600. `openProjectionSource` sirve sin cargar los vectores. `gcProjections` y `reconcileProjections` barren las obsoletas. |
| `binary-search.ts` | Hamming con xor + popcount de 32 bits; top-M O(n) por histograma, desempate por índice. |
| `rescore.ts` | Rescoring float32 (en memoria o por `pread` desde disco) e int8 asimétrico. |
| `quantized-search.ts` | Punto de entrada único listo para registrar como ruta. |

`FlatVectorStore` y `EmbeddingContract` no se tocan. Solo se añade el código `PROJECTION_MISMATCH` a `RagErrorCode`.

## Método

- **Segunda ejecución:** los datos de este informe son de una repetición completa tras corregir el script (la primera dio las mismas cifras de recall y solape; las latencias variaron con la carga de la máquina: float32 23 ms frente a 41 ms, embedding p50 910 ms frente a 156 ms). Las latencias absolutas son de una sola máquina y no son estables entre ejecuciones; las proporciones sí.
- **Real:** copia de `~/.savia-vaults/rag/savia-docs` a un directorio temporal (borrado al terminar). No se escribe en `~/.savia-vaults`. Generación `83c28bd3fa22`, 10 796 chunks, `qwen3-embedding:0.6b` (el digest vivo coincide con el del índice, comprobado antes de medir), 1024 dims.
- Banco: las 36 consultas de `eval/rag-savia-docs.json`. Búsqueda **densa sola** (no híbrida): lo que se cuantiza es el denso. La línea base híbrida registrada el 2026-09-29 es 0,806 / 0,566. La densa sola hoy es 0,736 / 0,561.
- Recall@10 y MRR a nivel de documento con las `relevantPaths` del banco (misma semántica que `rag eval`). «Solape@10» es la intersección de chunks con el top-10 del float32 exacto. «Top-1» es el acuerdo con el primer resultado exacto.
- Cada variante corre en un proceso nuevo (RSS propio). 1 calentamiento + 5 repeticiones por consulta (180 muestras reales).
- **Sintético (SINTÉTICO):** 1024 dims, 50 consultas. Mezcla de clusters (n/2000) en un espacio latente de 16 dim proyectado a 1024 más ruido. Repeticiones por consulta: 5 (10k), 2 (100k), 1 (1M, 50 muestras). Datos en `/tmp` (tmpfs).

## Resultados reales — savia-docs (medición propia)

Embedding de la consulta: p50 156 ms, p95 20 594 ms (cola por carga del modelo en Ollama). Construcción de la proyección: binaria 138 ms, int8 1 709 ms.

| Variante | Recall@10 | MRR | Solape@10 | Top-1 | p50 ms | p95 ms | RSS pico−base MB | Disco MB |
|---|---|---|---|---|---|---|---|---|
| float32 exacto | 0,736 | 0,561 | 1,000 | 1,00 | 40,6 | 52,6 | 204 | 44,2 |
| binario puro | 0,792 | 0,503 | 0,628 | 0,58 | 2,2 | 2,6 | 89 | 1,4 |
| bin M=50, f32 en RAM | 0,736 | 0,561 | 0,964 | 1,00 | 2,6 | 3,8 | 207 | 45,6 |
| bin M=50, f32 desde disco | 0,736 | 0,561 | 0,964 | 1,00 | 5,2 | 6,4 | 98 | 45,6 |
| bin M=100, f32 en RAM | 0,736 | 0,561 | 0,986 | 1,00 | 3,5 | 6,4 | 207 | 45,6 |
| bin M=100, f32 desde disco | 0,736 | 0,561 | 0,986 | 1,00 | 4,2 | 6,5 | 97 | 45,6 |
| bin M=200, f32 en RAM | 0,736 | 0,561 | 0,997 | 1,00 | 6,0 | 7,0 | 207 | 45,6 |
| bin M=200, f32 desde disco | 0,736 | 0,561 | 0,997 | 1,00 | 7,4 | 10,5 | 105 | 45,6 |
| bin M=400, f32 en RAM | 0,736 | 0,561 | 1,000 | 1,00 | 4,7 | 5,3 | 207 | 45,6 |
| bin M=400, f32 desde disco | 0,736 | 0,561 | 1,000 | 1,00 | 11,6 | 14,5 | 106 | 45,6 |
| int8 puro | 0,736 | 0,561 | 0,997 | 1,00 | 65,6 | 91,5 | 92 | 11,1 |
| int8 M=100 + f32 disco | 0,736 | 0,561 | 1,000 | 1,00 | 63,4 | 96,7 | 92 | 55,3 |
| int8 M=400 + f32 disco | 0,736 | 0,561 | 1,000 | 1,00 | 54,1 | 85,3 | 93 | 55,3 |

Lecturas y límites:
- «Binario puro» da Recall@10 0,792 > 0,736, pero su MRR cae y el solape es 0,63. Con 36 consultas y sin IC pareado no se puede afirmar que sea mejor: no se interpreta como ganancia.
- RSS: lo que se resta es el arranque de Node (~90 MB). Los ~90 MB del binario puro son sobre todo los 10 796 chunks (texto y metadatos) en objetos JS.
- Latencias con caché de página caliente. Los p95 se calculan sobre 180 muestras.

## Resultados sintéticos (SINTÉTICOS)

Solape@10 con el top-10 float32 exacto, p50/p95 en ms (solo búsqueda, sin embedding), RSS pico en MB y disco en MB.

| Variante | 10k solape | 10k p50/p95 | 100k solape | 100k p50/p95 | 1M solape | 1M p50/p95 |
|---|---|---|---|---|---|---|
| float32 exacto | 1,000 | 44,4 / 95,5 | 1,000 | 413 / 525 | 1,000 | 4 205 / 4 364 |
| binario puro | 0,532 | 2,0 / 3,3 | 0,486 | 15,8 / 20,5 | 0,514 | 201 / 403 |
| bin M=50 + f32 disco | 0,930 | 3,2 / 5,2 | 0,918 | 18,0 / 21,4 | 0,914 | 186 / 207 |
| bin M=100 + f32 disco | 0,992 | 3,8 / 4,1 | 0,974 | 18,3 / 25,3 | 0,984 | 169 / 207 |
| bin M=200 + f32 disco | 1,000 | 5,8 / 9,0 | 1,000 | 20,9 / 29,9 | 1,000 | 172 / 193 |
| bin M=400 + f32 disco | 1,000 | 8,8 / 11,8 | 1,000 | 24,7 / 29,9 | 1,000 | 166 / 190 |
| bin M=100 + f32 RAM | 0,992 | 2,5 / 4,5 | 0,974 | 17,9 / 31,3 | 0,984 | 155 / 183 |
| int8 puro | 0,974 | 45,0 / 59,7 | 0,956 | 496 / 620 | 0,952 | 4 771 / 5 316 |
| int8 M=100 + f32 disco | 1,000 | 47,0 / 95,3 | 1,000 | 491 / 565 | 1,000 | 4 857 / 6 000 |

| RSS pico MB | 10k | 100k | 1M |
|---|---|---|---|
| float32 exacto | 133 | 482 | 3 989 |
| binario puro | 120 | 126 | 247 |
| bin + f32 disco (M=100) | 112 | 123 | 249 |
| bin + f32 RAM (M=100) | 151 | 520 | 4 158 |
| int8 puro | 125 | 287 | 1 461 |

| Disco MB | 10k | 100k | 1M |
|---|---|---|---|
| float32 | 41,0 | 409,6 | 4 096 |
| + binario | +1,3 | +12,8 | +128 |
| + int8 | +10,2 | +102 | +1 024 |

Lecturas y límites:
- A 1 M, M=100 con rescoring conserva el 98,4 % del top-10 con una latencia ~25× menor; M=200 lo recupera entero en estos datos.
- Los sintéticos tienen una estructura que he fabricado. El solape real puede diferir; la coincidencia con savia-docs (0,964–1,000 para M=50–400) es consistente, no una prueba.
- El int8 en JS puro es más lento que el float32 (conversión int8 → double en el bucle) y no ahorra latencia: cuesta 4,8 s a 1 M. Un kernel nativo/SIMD es otra medición.
- Los p95 de 1 M salen de 50 muestras (1 repetición por consulta).

## Hallazgos de ingeniería

1. **Los chunks dominan la RAM, no los vectores.** `FlatVectorStore.load` mantiene texto y metadatos de todos los chunks. En savia-docs son ~60–90 MB por 10,8 k chunks, es decir ~6–8 KB por chunk. A 1 M de chunks serían ~6 GB, más que los 4 GB de float32. La cuantización solo baja la RAM si los chunks se cargan bajo demanda. Está fuera del alcance de M7 y no se hace aquí.
2. **Hueco de ciclo de vida en el `gc`, cerrado.** `RagService.gc` borraba enteras las generaciones retiradas (con sus proyecciones), pero en las que conserva `gcGeneration` solo limpiaba `chunks-/vectors-/bm25-`: las proyecciones de una seq anterior (signos de contenido que pudo borrarse o reclasificarse) se quedaban en disco. Ahora `gc` llama a `gcProjections`; un test con el `RagService` real recorre activa → sombra → promote → rollback → cambio de fuente → gc y comprueba que no queda ninguna proyección obsoleta (mutado: sin la llamada, el test falla).
3. **`resealIndex` reescribe en la misma seq con otra clave.** Una proyección sellada con la clave anterior deja de abrirse (falla cerrada) y hay que reconstruirla. **Pendiente**: no se ha tocado `resealIndex` ni hay test que lo cubra.
4. **El rescoring desde disco no vale con índices cifrados.** Exige descifrar el fichero entero; `DiskVectorReader` se niega. Un cifrado por bloques sería otro cambio.
5. **Sin proyección o con proyección que no casa, se rechaza**; nunca se sirve un resultado de una proyección ajena.

## Procedencia de cada cifra (R3)

| Cifra | Procedencia |
|---|---|
| Todas las de las tablas «reales» (recall, MRR, solape, latencias, RSS, disco, embedding p50) | medición propia, 36 consultas, 1 máquina, JS, dense-only |
| Todas las «sintéticas» | medición propia sobre datos fabricados |
| Umbral de ~50 000 vectores (100 ms) | extrapolación propia del coste por vector; el presupuesto de 100 ms es hipótesis |
| Línea base híbrida 0,806 / 0,566 | medición propia previa (2026-09-29), no repetida hoy |
| Rendimiento con kernels nativos/SIMD o con un índice ANN (HNSW) | hipótesis; no medido |
| Afirmaciones de terceros sobre cuantización | ninguna se usa para decidir |

## Estado respecto a SE-489

- La ruta M7 existe como punto de entrada (`QuantizedIndex.search`). **No está registrada como `RetrievalRoute`**, aunque la base ya está en main (#1432, mezclada en esta rama). El motivo es de contrato, no de plazo: `RouteContext.candidates(query, {k, mode})` solo ofrece el híbrido de `RagService` y no deja a una ruta cambiar la búsqueda densa. Registrarla exige tocar la base:
  1. una opción en `CandidateOptions` (p. ej. `dense`) que `RagService.search` pase a `searchStore`, y
  2. la carga por cúpula de la proyección de la generación activa (`QuantizedIndex.open(dir, nivel, cifrador)`), con `accept` derivado del guard.
  Es un cambio en el servicio y en el contexto de rutas; queda como seguimiento propio.
- No cambia el comportamiento por defecto de `vault_rag`.
- AC-3 (M7): cumplido para sombra/activa/rollback/GC (test con el `RagService` real). Pendiente la reconstrucción tras `resealIndex` (hallazgo 3).
- Decisión de promoción de M7: **descartar como defecto; opt-in para cúpulas > 50 000 vectores cuando existan chunks diferidos.** Las reglas de promoción de AC-6 se evalúan sobre el banco del conjunto de rutas, no aquí.

## Limitaciones de la medición

- `rssLoadedMB` de los datos sintéticos con float32 residente se toma antes de la carga perezosa de los vectores y es incorrecto; el informe usa el pico de RSS, que sí es válido.
- `scripts/bench-quantization.ts` no es importable desde un test (despacha al cargarse) y fija la clasificación `N2`.
- 36 consultas: sin IC por bootstrap pareado, y las diferencias de 1–2 consultas no son concluyentes.
- El payload sellado usa el `binding` como datos asociados del AEAD; `accept` es obligatorio en `QuantizedIndex.search`; `dims` ≥ 65 535 se rechazan.
- Tests: suite de savia-vaults 1 073/1 073 (en una ejecución anterior, un e2e ajeno agotó el timeout de 10 s con la máquina cargada).
