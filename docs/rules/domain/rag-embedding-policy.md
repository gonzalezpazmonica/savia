---
context_tier: L3
token_budget: 1100
spec: SE-410
---

# Política dinámica de embeddings — Savia RAG

> **Regla**: el índice RAG nunca contradice al contenido vigente sin declararlo y
> nunca mezcla espacios vectoriales. Implementación: `projects/savia-vaults/src/rag/`
> (`policy.ts`, `indexer.ts`, `service.ts`). Spec: `docs/specs/SE-410-savia-rag.spec.md`.

## P1 Contrato inmutable

Cada generación del índice tiene un contrato: proveedor, modelo, **digest** del
modelo, dimensiones, versión del chunker, `chunkChars`, `overlap` y prefijos de
consulta/documento. `generation = sha256(contrato canónico)[:12]`.

- El almacén rechaza cargar vectores con otro contrato (`CONTRACT_MISMATCH`).
- Las consultas se embeben con el contrato de la generación consultada. En un
  fan-out sobre cúpulas con modelos distintos, una vez **por contrato**.
- Si el modelo vivo ya no coincide con la generación activa, esa cúpula responde
  en BM25 con `status: degraded`. Nunca se compara una consulta con vectores de otro modelo.

## P2 Re-embedding por hash

sha256 por documento y por chunk (texto embebido + generación). Solo se embeben
chunks nuevos; los documentos borrados se purgan en el mismo sync. El `mtime` es
un atajo: si cambió pero el hash no, solo se actualiza el manifest.

## P3 Disparadores

| Disparador | Cuándo | Qué hace |
|---|---|---|
| Lectura | antes de cada búsqueda | si hay ≤ `inlineSyncBudget` (25) documentos pendientes, sync inline; si hay más, responde `stale` y el servidor MCP lanza sync en segundo plano |
| Escritura | `vault_write` | sync de la cúpula con debounce de 2 s |
| Modelo cargado | cada embedding | `keep_alive` (`SAVIA_RAG_KEEP_ALIVE`, def. `30m`) solo para el modelo de embedding |
| Programado | cada 6 h | `savia-vaults rag sync --all --check` (un lock ajeno no es fallo; exit 2 si el SLO falla) y `rag gc` |
| Checkpoint | semanal | `savia-vaults rag sync --all --rebuild --check` |

## P4 Deriva de modelo

Ollama puede actualizar un tag (`model:latest`) sin avisar. Cada sync compara el
digest vivo con el del contrato; si difiere, el contrato es otro y se construye
una generación **sombra**. La activa sigue sirviendo (en BM25 si su modelo ya no
existe) hasta la promoción.

## P5 Promoción con gate

| Caso | Regla |
|---|---|
| Primera generación de la cúpula | se activa sola al completarse |
| Sustituta con banco de eval | promueve si recall@10 ≥ activa y MRR ≥ activa − 0,02, con cobertura 100 % |
| Activa no evaluable en vivo (P4) | se compara con las métricas registradas al activarla |
| Sin banco de eval | solo `rag promote --force` (decisión humana) |

Se conserva la generación anterior para `rag rollback`; `rag gc` borra el resto.

## P6 Semántica temporal

- Excluidos salvo `includeStale`: frontmatter `status` en `excludeStatuses`
  (def. `deprecated`, `superseded`, `archived`) y `valid_until` vencido.
- `superseded_by` viaja en el hit como anotación.
- `halfLifeDays > 0`: `score × 0.5^(edad/halfLife)`. Edad por `modified`
  (o `updated`/`date`) del frontmatter; si falta, mtime.

## P7 Observabilidad y SLO

`savia-vaults rag status` por cúpula: generaciones, contrato, digest vivo vs
contrato, chunks, pendientes, `staleRatio`, `lagHours`, memoria.

- SLO: `staleRatio = 0` tras sync; `lagHours < 24` con cron activo.
- Alerta (`status --check` sale 2): `staleRatio > 0,10`, `lagHours >= 24`, digest
  distinto, cúpula habilitada sin generación, o cúpula con índice y
  `rag.enabled=false` (el cron la ignora y el índice envejece; L32/P8). Los
  umbrales son `STALE_RATIO_ALERT` y `LAG_HOURS_ALERT` en `policy.ts`.
- `rag sync --all` sale distinto de 0 (1; 2 con `--check`) con mensaje `ALERTA` en
  stderr si no hay cúpulas habilitadas o hay cúpulas indexadas deshabilitadas, y
  deja un evento `alert` en `rag.jsonl`. Cron: redirigir stderr al log y usar
  `savia-vaults rag status --check` como `success_check` de la automatización.
- Eventos en `$SAVIA_RAG_HOME/logs/rag.jsonl` (sync, gate, promote, rollback, corrupt).

## P8 Checkpoint de pipeline

Cambiar `CHUNKER_VERSION`, `chunkChars`, `overlap`, prefijos o modelo cambia el
contrato y genera una generación completa nueva, sujeta a P5.

## P9 Sin sustitutos silenciosos

El embedder de hash existe solo para tests (`SAVIA_RAG_TEST_PROVIDER=hash`) y su
contrato declara `provider: hash`. Si el proveedor configurado falla, la búsqueda
degrada a BM25 y lo dice en `detail`.

## Fusión entre cúpulas (SE-411)

Si todas las cúpulas de una búsqueda comparten contrato, los hits se ordenan por
coseno global (mismo espacio vectorial); si no, por rango con desempate
determinista y `fusion: "rank"` en la respuesta. Nunca depende del orden de la lista.

## Confidencialidad del índice

El índice copia texto de las notas: vive en `$SAVIA_RAG_HOME`
(def. `~/.savia-vaults/rag/`), con directorios `0700` y ficheros `0600`. El servicio
se niega a escribir dentro de un repo git. `"*"` nunca incluye cúpulas N4. Borrar el
directorio es seguro: se regenera.
