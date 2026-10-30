---
status: APPROVED
approved_at: 2026-09-29
approval: "Operadora 2026-09-29 en chat (AskUserQuestion): Aprobada, implementa"
priority: P1
developer_type: agent-single
created: 2026-09-29
author: Savia
phase: A
risk: L2
related_specs: [SE-286, SE-291, SE-293, SE-310, SE-327, SE-328, SE-330, SE-331, SE-395, SPEC-193]
origin: output/research/rag-agentes-as-is-20260929.md
resource: https://github.com/gonzalezpazmonica/pm-workspace/tree/main/projects/savia-vaults/src/rag
---

# SE-410 — Savia RAG: recuperación híbrida paralela en SaviaVaults

## Problema

`vault_search` es BM25 por documento. Falla con paráfrasis ("cómo evito que el
agente mergee sin permiso" no encuentra `autonomous-safety.md`) y devuelve
documentos enteros, no el fragmento útil. Cada llamada toca una cúpula: buscar
en savia-docs, SaviaLearning y Savia Labs son tres llamadas secuenciales y una
fusión a mano.

Sin embeddings no hay política de frescura, y al introducirlos aparecen los
fallos conocidos: vectores de documentos editados, borrados o deprecados se
siguen recuperando; un cambio de modelo (o del digest bajo el mismo tag) mezcla
espacios incompatibles; nadie mide cuánto va el índice por detrás del contenido.

## Solución

Módulo `src/rag/` en savia-vaults (TypeScript, **sin dependencias npm nuevas**),
servido por MCP y CLI:

1. **Chunking markdown** por encabezados: objetivo 1 200 caracteres, máx. 2 000,
   secciones < 200 se fusionan con la siguiente, solape 15 %. Cada chunk se
   embebe con cabecera contextual `título › h2 › h3` (contextual retrieval sin LLM).
2. **Embeddings locales** vía Ollama `/api/embed` por lotes (≤32 textos).
   Candidatos de licencia libre: Qwen3-Embedding-0.6B (Apache-2.0), BGE-M3 (MIT),
   granite-embedding-278m (Apache-2.0). El default sale del bake-off (S5).
3. **Almacén flat exacto** (Float32 normalizado, producto escalar) por cúpula y
   generación en `$SAVIA_RAG_HOME` (def. `~/.savia-vaults/rag/<dome>/<gen>/`),
   fuera del vault y de cualquier repo git.
4. **Híbrido**: BM25 (minisearch) sobre chunks + denso; top-50 de cada lista,
   RRF (k=60, pesos iguales), filtro de frescura, máx. 2 chunks por documento.
5. **Fan-out paralelo** cúpulas × consultas; fusión entre cúpulas por rango (RRF),
   nunca por score bruto (no comparable entre índices).
6. **Política dinámica de embeddings** (sección propia; canónica en
   `docs/rules/domain/rag-embedding-policy.md`).

qmd (MIT, Node, BM25+sqlite-vec+RRF+reranker, MCP) es la referencia de diseño;
no se adopta como dependencia: índice global sin ACL por cúpula ni N1-N4, sin
generaciones ni gate de promoción, binario nativo. LightRAG, RAGFlow,
LlamaIndex, Haystack y GraphRAG se descartan por Python/infra multi-servicio o
por duplicar la capa de grafo existente (SE-327/328). Detalle en el informe de origen.

## Contrato técnico

### Ficheros (`projects/savia-vaults/src/rag/`)

| Fichero | Responsabilidad |
|---|---|
| `types.ts` | `Chunk`, `EmbeddingContract`, `Manifest`, `RagHit`, `RagRequest`, `RagResponse`, `RagError` |
| `chunker.ts` | `chunkMarkdown(path, raw, opts)`; `CHUNKER_VERSION` |
| `embedder.ts` | `Embedder`; `OllamaEmbedder` (timeout 30 s, 1 reintento); `HashEmbedder` (solo tests) |
| `store.ts` | `FlatVectorStore`: escritura atómica, carga con verificación de contrato, `topK` |
| `indexer.ts` | `RagIndexer.sync()`: diff por hash, embed incremental, lock entre procesos |
| `retriever.ts` | `rrf`, `hybridSearch`, agregación por documento |
| `parallel.ts` | `Semaphore`, `withTimeout`, `fanOut` |
| `policy.ts` | frescura, decaimiento, SLO, `promotionDecision` |
| `service.ts` | `RagService` (una instancia por proceso; LRU de ≤4 índices cargados) |

### Entregables (rutas)

- Código: `projects/savia-vaults/src/rag/*.ts`; integración en
  `projects/savia-vaults/src/server/mcp.ts`, `projects/savia-vaults/src/cli/index.ts`,
  `projects/savia-vaults/src/registry/domes.ts`.
- Tests: `projects/savia-vaults/tests/unit/rag/*.test.ts`,
  `projects/savia-vaults/tests/integration/rag/*.test.ts`,
  `projects/savia-vaults/tests/e2e/mcp-rag.test.ts`, `projects/savia-vaults/tests/e2e/cli-rag.test.ts`.
- Configuración y eval: `projects/savia-vaults/savia-vaults.domes.json`,
  `projects/savia-vaults/eval/rag-savia-docs.json`.
- Política y operación: `docs/rules/domain/rag-embedding-policy.md`,
  `.claude/skills/savia-vaults/SKILL.md`.
- Documentación y planificación: `projects/savia-vaults/README.md`,
  `projects/savia-vaults/CHANGELOG.md`, `docs/propuestas/planning-state.json`,
  `docs/propuestas/LOG.md`, `docs/propuestas/ROADMAP-CURRENT.md`.

### Tipos principales

```ts
interface EmbeddingContract {
  provider: 'ollama' | 'hash'; model: string; modelDigest: string; dims: number;
  normalize: true; chunkerVersion: string; chunkChars: number; overlap: number;
  queryPrefix: string; docPrefix: string;
}
// generationId = sha256(JSON canónico del contrato).slice(0, 12)

interface Embedder {
  contract(): Promise<EmbeddingContract>;          // resuelve digest y dims reales
  embed(texts: string[], kind: 'query' | 'doc'): Promise<Float32Array[]>;  // normalizados
}

interface SyncReport {
  dome: string; generation: string; promoted: boolean; shadow: boolean;
  docs: { added: number; updated: number; deleted: number; unchanged: number };
  chunks: { total: number; embedded: number; reused: number };
  durationMs: number;
}

interface RagHit {
  dome: string; confidentiality: 'N1'|'N2'|'N3'|'N4';
  path: string; heading: string; text: string;          // chunk, recortado a presupuesto
  score: number;                                        // RRF (tras decaimiento)
  signals: { denseRank?: number; bm25Rank?: number; dense?: number; bm25?: number };
  freshness: { modified: string; status?: string; supersededBy?: string; decay: number };
  generation: string;
}

interface RagResponse {
  results: { query: string; hits: RagHit[] }[];
  merged?: RagHit[];                                    // >1 consulta: RRF de todas
  domes: { name: string; status: 'ok'|'stale'|'degraded'|'denied'|'timeout'|'error'|'not_indexed';
           generation?: string; detail?: string }[];
  timings: { totalMs: number; embedMs: number; syncMs: number };
}
```

### Qué se indexa

Ficheros `.md` del vault ≤ 1 MB; se saltan directorios que empiezan por `.`
(`.git`, `.trash`, `.savia-vault`), `node_modules` y las rutas denegadas por
`VaultSecurity`. **CRIT-001**: una nota cuyo frontmatter `confidentiality` supera
el nivel de su cúpula (p. ej. N3 en una cúpula N2) no se embebe; queda en el
manifest como `skipped` para no figurar como pendiente. Frontmatter fuera del texto embebido; `title`, `status`,
`valid_until`, `superseded_by` y `modified` pasan a metadatos del chunk.

### Límites de entrada (validados; error tipado si se exceden)

`queries` ≤ 8, cada una 1-1 000 caracteres; `k` 1-50 (def. 8); `domes` debe
nombrar cúpulas registradas; `maxChars` total de `text` en la respuesta
(def. 12 000; se recorta el texto, nunca se omite un hit).

### Orden de ejecución de una búsqueda

1. Validar entrada; expandir `"*"` a cúpulas activas con `rag.enabled`, **sin N4**.
2. Autorizar cada cúpula por separado (`AccessController`, acción `read`);
   denegadas → `status: denied`, 0 hits. Cuotas y auditoría SE-293 por cúpula.
3. Frescura por cúpula en paralelo (semáforo `concurrency`, def. 4): disparador P3-lectura.
4. Agrupar cúpulas por contrato; embeber **todas** las consultas en un lote por
   contrato (P1: una consulta nunca se compara con vectores de otro contrato).
5. Puntuar cada (cúpula, consulta) en paralelo con timeout por tarea (def. 8 s).
6. Fusionar por consulta y, si hay varias, `merged` global. Devolver estados y tiempos.

### MCP

| Tool | Permiso | Entrada |
|---|---|---|
| `vault_rag` | `read` por cúpula | `query` \| `queries[]`, `domes[]` \| `"*"`, `k`, `mode` (`hybrid`\|`dense`\|`bm25`), `pathPrefix`, `includeStale`, `maxChars` |
| `vault_rag_status` | `read` | `domes[]` opcional |
| `vault_rag_sync` | `write` | `dome`, `rebuild` |

Los hits son **datos no confiables** (SPEC-193): llevan `dome`, `confidentiality`,
`path` y `generation` para procedencia; el servidor no interpreta su contenido.

### CLI

```
savia-vaults rag search <q...> [--domes a,b|all] [--k 8] [--mode hybrid]
                               [--concurrency 4] [--timeout 8000] [--json]
savia-vaults rag sync     [--dome X | --all] [--rebuild] [--check]
savia-vaults rag status   [--dome X] [--json] [--check]
savia-vaults rag eval     --dome X [--queries f.json] [--generation id] [--mode m] [--json]
savia-vaults rag promote  <dome> <generation> [--force]
savia-vaults rag rollback <dome>
savia-vaults rag gc       [--dome X]
```

### Configuración por cúpula (bloque opcional `rag` en `savia-vaults.domes.json`)

```json
"rag": { "enabled": true, "model": "qwen3-embedding:0.6b", "chunkChars": 1200,
         "overlap": 0.15, "halfLifeDays": 0,
         "excludeStatuses": ["deprecated", "superseded", "archived"],
         "evalSet": "<ruta relativa al vault>", "inlineSyncBudget": 25 }
```

Precedencia: argumento > bloque `rag` > env (`SAVIA_RAG_MODEL`, `SAVIA_RAG_HOME`,
`SAVIA_OLLAMA_URL`) > defaults. Sin bloque `rag`, la cúpula no se indexa.

### Persistencia, concurrencia y confidencialidad

- Generación = `manifest.json` + `chunks-<seq>.jsonl` + `vectors-<seq>.f32`.
  Escritura en ficheros nuevos y `rename` atómico del manifest; un lector siempre
  ve un snapshot completo. `gc` borra `seq` no referenciados con > 10 min.
- `active.json` por cúpula apunta a la generación activa y a la anterior (rollback).
- Lock de sync por cúpula: fichero `O_EXCL` con pid y timestamp; se considera
  huérfano si el pid no existe o tiene > 10 min. Servidores MCP de Claude Code y
  OpenCode y la CLI pueden coexistir.
- El índice copia texto de las notas: directorios `0700`, ficheros `0600`. Si
  `SAVIA_RAG_HOME` cae dentro de un repo git, el servicio se niega a escribir.
  Borrar `$SAVIA_RAG_HOME` es siempre seguro (se regenera).

## Política dinámica de embeddings

Objetivo: el índice nunca contradice al contenido vigente sin declararlo y nunca
mezcla espacios vectoriales.

- **P1 Contrato inmutable.** Cada generación tiene su `EmbeddingContract`; su hash
  es el id. El store rechaza cargar vectores con otro contrato (`RagError
  CONTRACT_MISMATCH`). Las consultas se embeben con el contrato de la generación
  que se consulta.
- **P2 Cambio por hash.** sha256 por documento (bytes) y por chunk (texto
  embebido + id de contrato). Solo se embeben chunks cuyo hash no está en la
  generación; los de documentos borrados se purgan en el mismo sync.
- **P3 Disparadores.**
  - *Lectura*: fingerprint barato (count + max mtime, SE-310). Si cambió y hay
    ≤ `inlineSyncBudget` documentos pendientes: sync inline. Si hay más: se sirve
    la generación actual con `status: stale`; el servidor MCP lanza sync en
    segundo plano (uno por cúpula); la CLI no lanza nada y lo indica.
  - *Escritura*: `vault_write` programa sync de esa cúpula con debounce de 2 s.
  - *Programado*: `savia-vaults rag sync --all --check` (sin script aparte: no suma
    capacidades al registry, ratchet SE-380)
    cada 6 h; `--rebuild` semanal en generación sombra como checkpoint.
- **P4 Deriva de modelo.** Cada sync compara el digest actual de Ollama con el
  del contrato. Si difiere, construye una generación **sombra**; la activa sigue
  sirviendo hasta la promoción.
- **P5 Promoción.** La primera generación de una cúpula se activa sola al
  completarse (no hay nada que empeorar). Una sustituta se promueve si, sobre el
  banco de eval de la cúpula y en la misma ejecución: recall@10 ≥ activa,
  MRR ≥ activa − 0,02 y cobertura = 100 % de documentos. Sin banco de eval: solo
  `promote --force` (decisión humana). Se conserva la anterior para `rollback`.
- **P6 Semántica temporal.** Excluidos salvo `includeStale`: `status` en
  `excludeStatuses`, `valid_until` vencido. `superseded_by` viaja como anotación.
  Con `halfLifeDays > 0`: `score × 0.5^(edad/halfLife)`, edad por `modified` del
  frontmatter o, si falta, mtime.
- **P7 Observabilidad.** `rag status` por cúpula: generación activa/sombra/anterior,
  contrato, digest actual vs contrato, chunks, documentos pendientes,
  `staleRatio`, `lagHours`, edad de la generación. SLO: `staleRatio = 0` tras sync;
  `lagHours < 24` con cron. `status --check` sale 2 si `staleRatio > 0,10`, `lagHours >= 24`, digest
  distinto, cúpula habilitada sin generación o cúpula con índice y `rag.enabled=false`. Eventos en `$SAVIA_RAG_HOME/logs/rag.jsonl`.
- **P8 Checkpoint.** Cambiar `CHUNKER_VERSION`, `chunkChars`, `overlap`, prefijos
  o modelo cambia el contrato ⇒ generación nueva completa, sujeta a P5.
- **P9 Sin sustitutos silenciosos.** `HashEmbedder` nunca se usa fuera de tests.
  Si el proveedor configurado falla, se degrada a BM25 declarándolo.

## Degradación

| Fallo | Comportamiento |
|---|---|
| Ollama caído | `hybrid`/`dense` → BM25 con `status: degraded` y `detail` |
| Cúpula sin generación | `not_indexed`; el resto responde |
| Timeout de cúpula | `timeout`; hits del resto |
| Lock ocupado | búsqueda sobre la generación activa; `sync` CLI sale con código 3 |
| Índice corrupto / contrato distinto | `error` con `detail`; sugerencia `rag sync --rebuild` |

## Evaluación y selección de modelo (S5)

Banco `projects/savia-vaults/eval/rag-savia-docs.json`, fijado **antes** de medir:
≥ 30 consultas en español; ≥ 60 % paráfrasis sin los términos distintivos del
documento objetivo y ≥ 25 % léxicas (IDs, nombres de fichero, flags), campo `kind`.
Métricas: recall@5, recall@10, MRR para `bm25`, `dense`, `hybrid` y cada modelo.
Línea base adicional: `vault_search` actual (BM25 por documento), para medir la
mejora real que percibe un agente. Regla de elección: mayor MRR `hybrid`; empate
(< 0,01) → menor latencia de embed. Parámetros de chunking fijos durante el
bake-off (sin ajuste al banco). Latencia: `rag eval --json` registra el tiempo de
cada consulta (≥ 30, en caliente) y reporta p50/p95.

## Resultados (2026-09-29)

Banco savia-docs (36 consultas, prerregistrado en commit `b1cfcc76` antes de medir):

| Modo | recall@5 | recall@10 | MRR |
|---|---|---|---|
| `vault_search` actual (BM25 por documento) | — | 0,347 | 0,251 |
| bm25 por chunk | 0,556 | 0,639 | 0,479 |
| dense qwen3-embedding:0.6b | 0,694 | 0,736 | 0,563 |
| **hybrid qwen3-embedding:0.6b** | 0,694 | **0,806** | **0,566** |
| dense granite-embedding:278m | 0,750 | 0,861 | 0,590 |
| hybrid granite-embedding:278m | 0,667 | 0,833 | 0,554 |

- Regla de elección aplicada: mayor MRR híbrido → qwen3-embedding:0.6b (0,566 vs
  0,554). Con n=36 la diferencia entre modelos no es significativa; granite es el
  mejor en modo denso y 3× más rápido indexando (180 s vs 538 s). Se revisa con un
  banco mayor.
- BGE-M3 excluido por fiabilidad, no por calidad: en Ollama sobre la GPU local
  devuelve NaN en el 95,8 % de los chunks (`json: unsupported value: NaN`).
- La primera medición de BM25 por chunk (MRR 0,385) reveló dos defectos: sin
  stopwords es/en y prefijo sobre tokens de 2 letras. Corregidos (stopwords,
  plegado de acentos, prefijo ≥ 4, fuzzy ≥ 5) antes de la elección; no se tocaron
  pesos ni parámetros de chunking.
- AC1 cumplido con qwen3: +0,087 MRR y +0,167 recall@10 sobre bm25; híbrido ≥ denso.
- AC2: editar 1 documento de savia-docs (copia) embebe 2 chunks; sync 667 ms
  (1,5 s de pared con arranque de la CLI). Borrado purgado en el siguiente sync.
- AC10 (proceso en caliente, como el servidor MCP): una cúpula p95 179 ms; 3
  cúpulas × 3 consultas p95 302 ms. La primera llamada de un proceso nuevo tarda
  ~2,4 s (carga del índice de 44 MB y BM25 sobre 10 796 chunks): la CLI la paga
  en cada invocación.
- Savia Labs (banco privado, 18 consultas): hybrid recall@10 0,963, MRR 0,958
  frente a bm25 0,824 / 0,773; la única nota N3 de la cúpula no se embebió.
- Indexación completa: savia-docs 536 s (10 796 chunks), Labs 37 s (704 chunks).

## Slices y esfuerzo

| Slice | Contenido | Agente | Humano |
|---|---|---|---|
| S1 | chunker, embedder, store, indexer incremental + lock | 3 h | 1 h |
| S2 | retriever híbrido + fan-out paralelo | 2 h | 45 min |
| S3 | MCP (3 tools) + CLI `rag` + ACL/N4 + límites | 2 h | 45 min |
| S4 | política: frescura, generaciones, promote/rollback/gc, status/SLO, cron vía CLI | 2 h | 45 min |
| S5 | banco de eval, bake-off, perfil Savia Labs (banco privado en su vault) | 2 h | 1 h |
| S6 | README, regla de política, skill savia-vaults, CHANGELOG | 1 h | 30 min |

Total: 12 h agente, ~4,75 h humano, 30 min de review.

## Criterios de aceptación

- **AC1** Calidad (prerregistrado): en el banco de savia-docs con el modelo
  elegido, `hybrid` ≥ `bm25` + 0,05 en MRR y en recall@10, y `hybrid` ≥ `dense` − 0,02
  en MRR. Se publican las cifras de los tres modos y de cada modelo.
- **AC2** Incremental: tras editar 1 documento, `rag sync` embebe solo sus chunks
  nuevos (`embedded` = chunks con hash nuevo) y tarda < 3 s con el modelo cargado.
- **AC3** Borrado: un documento borrado no aparece en ninguna búsqueda posterior.
- **AC4** Contrato: cargar con otro contrato lanza `CONTRACT_MISMATCH`; un fan-out
  sobre dos contratos embebe cada consulta una vez por contrato.
- **AC5** Deprecado: `status: deprecated` no aparece salvo `includeStale: true`;
  `superseded_by` aparece anotado.
- **AC6** Paralelo: 3 cúpulas × 3 consultas en una llamada; con una cúpula en
  timeout, las otras devuelven hits y esa figura `timeout`.
- **AC7** ACL: con auth activa y token sin permiso sobre una cúpula, figura
  `denied` con 0 hits; `"*"` nunca incluye una cúpula N4.
- **AC8** Degradación: con Ollama inaccesible, `vault_rag` responde BM25 `degraded`.
- **AC9** Generaciones: una sombra que empeora recall@10 no se promueve sin
  `--force`; `rollback` restaura la anterior y la búsqueda la usa; un lector
  concurrente con un sync nunca ve un snapshot parcial.
- **AC10** Latencia (GPU local, modelo cargado, índice al día): p95 de una cúpula
  < 400 ms; 3 cúpulas × 3 consultas < 1,5 s.
- **AC11** Confidencialidad: ficheros del índice `0600`; negativa a escribir si
  `SAVIA_RAG_HOME` está dentro de un repo git.
- **AC12** Tests: los 349 existentes siguen verdes; nuevos tests unitarios, de
  integración y e2e MCP cubren AC2-AC9 y AC11 con `HashEmbedder`, sin red. El test
  live contra Ollama se omite solo si Ollama no responde (dependencia de entorno declarada).
- **AC14** CRIT-001: una nota N3 en una cúpula N2 no produce ningún chunk ni
  vector; en una cúpula N4 sí se indexa.
- **AC13** Savia Labs: perfil `rag` activo, banco de eval privado (≥ 15 consultas)
  dentro de su vault, generación activa con cifras de eval registradas allí;
  ningún contenido de Labs en el repo público.

## Plan de tests

| Fichero (`tests/unit/rag/`, `tests/integration/`, `tests/e2e/`) | Cubre |
|---|---|
| `chunker.test.ts` | encabezados, fusión de secciones cortas, máx. 2 000, solape, cabecera contextual |
| `store.test.ts` | round-trip, `CONTRACT_MISMATCH`, rename atómico, permisos 0600, negativa dentro de git (AC4, AC11) |
| `indexer.test.ts` | incremental por hash, purga de borrados, lock huérfano, primera generación auto-activa (AC2, AC3) |
| `policy.test.ts` | exclusión por status/`valid_until`, `superseded_by`, decaimiento, `promotionDecision`, SLO (AC5, AC9) |
| `retriever.test.ts` | RRF, tope por documento, modos, recorte `maxChars` |
| `parallel.test.ts` | semáforo, timeout parcial, un embed por contrato (AC4, AC6) |
| `rag-service.test.ts` (integración) | fan-out con cúpula denegada y N4 fuera de `"*"`, degradación sin Ollama, rollback, lector durante sync (AC6-AC9) |
| `mcp-rag.test.ts` (e2e) | `tools/list` y llamadas reales a las tres tools por stdio |
| `cli-rag.test.ts` (e2e) | `rag sync --all --check`: exit 0/2, lock ajeno no es fallo, entrada inválida |
| `rag-live.test.ts` | Ollama real; omitido solo si `/api/tags` no responde |

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Banco de eval sesgado a favor del denso | cuota de consultas léxicas y relevancia fijada antes de medir |
| Memoria (flat en RAM) | ~4 KB/chunk a 1024 dims; LRU de 4 índices; aviso en `status` > 250 MB |
| Deriva silenciosa del tag de Ollama | P4 compara digest en cada sync |
| Copias de texto N3/N4 fuera del vault | permisos, fuera de git, N4 fuera de `"*"` |

## Dependencias

SE-291 (ACL multi-cúpula), SE-293 (cuotas/auditoría), SE-310 (fingerprint),
SE-331 (métricas), SPEC-193 (procedencia). Ollama local con un modelo de embedding.

## Rollout y reversión

Aditivo: `vault_search` no cambia. Reversión: quitar las tres tools y borrar
`$SAVIA_RAG_HOME`. Activación por cúpula con el bloque `rag`.

## Fuera de alcance

Reranker (interfaz prevista, v2), expansión de consulta por LLM, RAG federado
A2A, índice ANN mientras haya < 200k chunks, ruido de tags `#NNN` en BM25 de
`vault_search`, truncado Matryoshka.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| MCP savia-vaults (`vault_rag*`) | `~/.claude.json` | `opencode.json` `mcp.savia-vaults` (mismo binario) |
| CLI `savia-vaults rag` (incl. cron `rag sync --all --check`) | bash | idéntico |

### Verification protocol

- [ ] `tools/list` expone las tres tools en ambos frontends
- [ ] `rag search` devuelve lo mismo desde ambos

### Portability classification

- [x] **PURE_NODE** (servidor MCP stdio; sin hooks ni IDs de proveedor en frontmatter)
