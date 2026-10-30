# SE-489 M7 — Cuantización en sombra: medición sobre savia-docs y a escala sintética

Fecha: 2026-10-30. Rama `agent/se489-m7-20261023`. Datos crudos: `docs/audits/20261030-se489-m7-datos/`.
Reproducción: `projects/savia-vaults/scripts/bench-quantization.ts` (`real` y `synth`).

## Conclusión

1. **En savia-docs no compensa.** Con 10 796 chunks el float32 pesa 44 MB y una búsqueda exacta tarda 23 ms (p50). Embeber la consulta tarda 910 ms (p50): la búsqueda es el 2,5 % de la latencia. Binario + rescoring (M=100) baja la búsqueda a 2,2 ms; el usuario no lo nota.
2. **Recall perdido en savia-docs, dense-only, 36 consultas:**
   - Binario + rescoring float32: **0 pp** en Recall@10 y MRR frente al float32 exacto, para M = 50, 100, 200 y 400 (0,736 / 0,561 en todos).
   - A nivel de chunk, el solape del top-10 con el exacto es 0,964 (M=50), 0,986 (M=100), 0,997 (M=200), 1,000 (M=400). M=100 pierde 1,4 pp de chunks, y ninguno cambia la lista de documentos.
   - Binario puro sin rescoring: solape 0,628, MRR 0,503 (−0,058). No usar.
   - int8: solape 0,997, mismo Recall@10 y MRR. Pierde 0,3 pp, pero en JS es más lento que el float32.
3. **Umbral de tamaño.**
   - Latencia: la búsqueda exacta cuesta ~2,1 µs por vector (1024 dims, JS). Pasa de 100 ms hacia **~50 000 vectores**; con 100 000 son 415 ms frente a 18 ms binario (23×); con 1 M, 4,2 s frente a 0,16 s (26×). El presupuesto de 100 ms es supuesto mío, no una cifra de la spec.
   - Memoria: la proyección binaria con rescoring desde disco evita tener el float32 residente (4 GB a 1 M vectores; 250 MB de pico en la medición sintética). **Solo si además los chunks dejan de cargarse en RAM** (ver «Hallazgos»). Con el índice actual, el ahorro de RAM a 1 M sería falso.
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

- **Real:** copia de `~/.savia-vaults/rag/savia-docs` a un directorio temporal (borrado al terminar). No se escribe en `~/.savia-vaults`. Generación `83c28bd3fa22`, 10 796 chunks, `qwen3-embedding:0.6b` (el digest vivo coincide con el del índice, comprobado antes de medir), 1024 dims.
- Banco: las 36 consultas de `eval/rag-savia-docs.json`. Búsqueda **densa sola** (no híbrida): lo que se cuantiza es el denso. La línea base híbrida registrada el 2026-09-29 es 0,806 / 0,566. La densa sola hoy es 0,736 / 0,561.
- Recall@10 y MRR a nivel de documento con las `relevantPaths` del banco (misma semántica que `rag eval`). «Solape@10» es la intersección de chunks con el top-10 del float32 exacto. «Top-1» es el acuerdo con el primer resultado exacto.
- Cada variante corre en un proceso nuevo (RSS propio). 1 calentamiento + 5 repeticiones por consulta (180 muestras reales).
- **Sintético (SINTÉTICO):** 1024 dims, 50 consultas. Mezcla de clusters (n/2000) en un espacio latente de 16 dim proyectado a 1024 más ruido. Repeticiones por consulta: 5 (10k), 2 (100k), 1 (1M, 50 muestras). Datos en `/tmp` (tmpfs).

## Resultados reales — savia-docs (medición propia)

Embedding de la consulta: p50 910 ms, p95 1 588 ms. Construcción de la proyección: binaria 117 ms, int8 1 352 ms.

| Variante | Recall@10 | MRR | Solape@10 | Top-1 | p50 ms | p95 ms | RSS pico−base MB | Disco MB |
|---|---|---|---|---|---|---|---|---|
| float32 exacto | 0,736 | 0,561 | 1,000 | 1,00 | 23,1 | 30,1 | 205 | 44,2 |
| binario puro | 0,792 | 0,503 | 0,628 | 0,58 | 1,7 | 1,9 | 90 | 1,4 |
| bin M=50, f32 en RAM | 0,736 | 0,561 | 0,964 | 1,00 | 1,9 | 2,2 | 207 | 45,6 |
| bin M=50, f32 desde disco | 0,736 | 0,561 | 0,964 | 1,00 | 2,4 | 2,6 | 96 | 45,6 |
| bin M=100, RAM | 0,736 | 0,561 | 0,986 | 1,00 | 2,2 | 3,9 | 207 | 45,6 |
| bin M=100, disco | 0,736 | 0,561 | 0,986 | 1,00 | 3,1 | 3,6 | 101 | 45,6 |
| bin M=200, RAM | 0,736 | 0,561 | 0,997 | 1,00 | 2,7 | 3,2 | 206 | 45,6 |
| bin M=200, disco | 0,736 | 0,561 | 0,997 | 1,00 | 4,6 | 5,0 | 102 | 45,6 |
| bin M=400, RAM | 0,736 | 0,561 | 1,000 | 1,00 | 3,7 | 4,3 | 207 | 45,6 |
| bin M=400, disco | 0,736 | 0,561 | 1,000 | 1,00 | 7,3 | 7,9 | 106 | 45,6 |
| int8 puro | 0,736 | 0,561 | 0,997 | 1,00 | 41,0 | 54,6 | 93 | 11,1 |
| int8 M=100 + f32 disco | 0,736 | 0,561 | 1,000 | 1,00 | 42,5 | 63,8 | 93 | 55,3 |
| int8 M=400 + f32 disco | 0,736 | 0,561 | 1,000 | 1,00 | 47,2 | 57,6 | 93 | 55,3 |

Lecturas y límites:
- «Binario puro» da Recall@10 0,792 > 0,736, pero su MRR cae y el solape es 0,63. Con 36 consultas y sin IC pareado no se puede afirmar que sea mejor: no se interpreta como ganancia.
- RSS: lo que se resta es el arranque de Node (~90 MB). Los ~90 MB del binario puro son sobre todo los 10 796 chunks (texto y metadatos) en objetos JS.
- Latencias con caché de página caliente. Los p95 se calculan sobre 180 muestras.

## Resultados sintéticos (SINTÉTICOS)

Solape@10 con el top-10 float32 exacto, p50/p95 en ms (solo búsqueda, sin embedding), RSS pico en MB y disco en MB.

| Variante | 10k solape | 10k p50/p95 | 100k solape | 100k p50/p95 | 1M solape | 1M p50/p95 |
|---|---|---|---|---|---|---|
| float32 exacto | 1,000 | 35 / 62 | 1,000 | 415 / 717 | 1,000 | 4 193 / 7 508 |
| binario puro | 0,532 | 1,9 / 4,1 | 0,486 | 19,7 / 32,9 | 0,514 | 163 / 221 |
| bin M=50 + f32 disco | 0,930 | 2,2 / 2,6 | 0,918 | 17,8 / 26,3 | 0,914 | 170 / 228 |
| bin M=100 + f32 disco | 0,992 | 2,9 / 4,4 | 0,974 | 18,5 / 24,3 | 0,984 | 161 / 233 |
| bin M=200 + f32 disco | 1,000 | 4,9 / 9,0 | 1,000 | 23,0 / 26,7 | 1,000 | 165 / 229 |
| bin M=400 + f32 disco | 1,000 | 7,2 / 8,1 | 1,000 | 20,2 / 25,9 | 1,000 | 170 / 246 |
| bin M=100 + f32 RAM | 0,992 | 2,0 / 2,2 | 0,974 | 18,0 / 28,0 | 0,984 | 159 / 257 |
| int8 puro | 0,974 | 38,5 / 50,0 | 0,956 | 517 / 879 | 0,952 | 5 495 / 14 628 |
| int8 M=100 + f32 disco | 1,000 | 39,7 / 50,6 | 1,000 | 488 / 764 | 1,000 | 5 839 / 16 522 |

| RSS pico MB | 10k | 100k | 1M |
|---|---|---|---|
| float32 exacto | 132 | 484 | 3 997 |
| binario puro | 121 | 126 | 250 |
| bin + f32 disco (M=100) | 119 | 131 | 253 |
| bin + f32 RAM (M=100) | 147 | 524 | 4 156 |
| int8 puro | 130 | 292 | 1 462 |

| Disco MB | 10k | 100k | 1M |
|---|---|---|---|
| float32 | 41,0 | 409,6 | 4 096 |
| + binario | +1,3 | +12,8 | +128 |
| + int8 | +10,2 | +102 | +1 024 |

Lecturas y límites:
- A 1 M, M=100 con rescoring conserva el 98,4 % del top-10 con una latencia 26× menor; M=200 lo recupera entero en estos datos.
- Los sintéticos tienen una estructura que he fabricado. El solape real puede diferir; la coincidencia con savia-docs (0,964–1,000 para M=50–400) es consistente, no una prueba.
- El int8 en JS puro es más lento que el float32 (conversión int8 → double en el bucle) y no ahorra latencia: cuesta 5,5 s a 1 M. Un kernel nativo/SIMD es otra medición.
- Los p95 de int8 a 1 M (14–16 s) vienen con 1 repetición y presión de memoria; son indicativos, no estables.

## Hallazgos de ingeniería

1. **Los chunks dominan la RAM, no los vectores.** `FlatVectorStore.load` mantiene texto y metadatos de todos los chunks. En savia-docs son ~60–90 MB por 10,8 k chunks, es decir ~6–8 KB por chunk. A 1 M de chunks serían ~6 GB, más que los 4 GB de float32. La cuantización solo baja la RAM si los chunks se cargan bajo demanda. Está fuera del alcance de M7 y no se hace aquí.
2. **Hueco de ciclo de vida en el `gc` actual.** `RagService.gc` borra enteros los directorios de generaciones retiradas (con sus proyecciones) pero, en las que conserva, `gcGeneration` solo limpia `chunks-/vectors-/bm25-`. Un test con el `RagService` real reproduce que las proyecciones de una seq anterior se quedan en disco. Contienen signos de contenido que pudo borrarse o reclasificarse. Se rechazan al cargar, pero siguen ahí. `reconcileProjections` las barre; **hay que llamarlo desde `gc`** (pendiente, cambio en `service.ts` fuera de este alcance).
3. **`resealIndex` reescribe en la misma seq con otra clave.** Una proyección sellada con la clave anterior dejaría de abrirse (falla cerrada, correcto) y habría que reconstruirla. Pendiente en el mismo punto de integración.
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

- La ruta M7 existe como punto de entrada (`QuantizedIndex.search`). **No está registrada como `RetrievalRoute`**: la base (`agent/se489-base-20261030`) no existía en origin al terminar. El adaptador pendiente es una envoltura de `search` con la traza y el `accept` de autorización.
- No cambia el comportamiento por defecto de `vault_rag`.
- AC-3 (M7): test de ciclo de vida con el `RagService` real que reproduce el hueco de `gc` y comprueba que `reconcileProjections` no deja proyecciones obsoletas. La integración en `gc` queda pendiente (hallazgo 2).
- Decisión de promoción de M7: **descartar como defecto; opt-in para cúpulas > 50 000 vectores cuando existan chunks diferidos.** Las reglas de promoción de AC-6 se evalúan sobre el banco del conjunto de rutas, no aquí.

## Limitaciones de la medición

- `rssLoadedMB` de los datos sintéticos con float32 residente se tomó antes de la carga perezosa de los vectores y es incorrecto. Esta tabla usa el pico de RSS, que sí es válido. El script conserva la medición tal cual se ejecutó.
- 36 consultas: sin IC por bootstrap pareado, y las diferencias de 1–2 consultas no son concluyentes.
- Tests: la suite de savia-vaults da 1 065 de 1 066. Un test e2e ajeno (`mcp-registry-reload`, `--rag-autosync`) agotó los 10 s en la ejecución completa con la máquina cargada; pasa solo en 3 s.
