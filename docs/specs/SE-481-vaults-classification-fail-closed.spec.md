---
status: APPROVED
priority: P0
developer_type: agent-single
created: 2026-10-30
approved_at: 2026-10-30
author: Savia
phase: D
risk: L3
related_specs: [SE-410, SE-417, SE-419, SE-420, SE-480, SE-482]
origin: propuesta externa «Savia Vaults — del RAG híbrido al contexto gobernado» v0.1 (F0 y primer corte §7.1), verificada contra HEAD 7b434f9ae; decisión de la operadora 2026-10-30 (AskUserQuestion) — clasificación explícita inválida va a cuarentena
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-481 — Vaults: clasificación con cierre seguro y polaridad en la búsqueda léxica

## Problema (verificado contra HEAD 7b434f9ae)

1. **Clasificación explícita rota se sirve como «sin nivel» (H1, CONFIRMADO).**
   - `src/rag/chunker.ts::parseNote()` captura el error del YAML y sigue sin metadatos.
   - `src/storage/note-level.ts::noteLevel()` delega en `parseNote`. Con `confidentiality: [N4` en el frontmatter, el resultado es `undefined`.
   - `exceedsDomeLevel()` devuelve `false` para un nivel ausente **y también para un nivel desconocido** (`N7`, `secreto`).
   - Resultado: una nota que su autora quiso proteger aparece en `vault_read`, `vault_search` y `vault_rag` de una cúpula N2.
2. **El RAG no revalida al servir.**
   - El nivel por nota se comprueba al indexar (`src/rag/indexer.ts`).
   - Los fragmentos de una generación ya construida se sirven sin volver a mirar el nivel actual. Una reclasificación al alza no surte efecto hasta el siguiente sync.
3. **Tipos desalineados.**
   - `src/rag/types.ts` declara `Confidentiality = 'N1'|'N2'|'N3'|'N4'`.
   - `note-level.ts` reconoce también `N4B`, que es un nivel canónico de la ontología N1-N4b del workspace.
4. **Negaciones eliminadas (H2, CONFIRMADO).**
   - `src/rag/retriever.ts` trata `no`, `not`, `ni`, `sin` y `nada` como stopwords.
   - Las consultas «no está permitido X» y «está permitido X» producen la misma consulta BM25.

## Decisión

Una clasificación **explícita** que no se puede interpretar va a **cuarentena**:

- no se indexa;
- no se sirve por ninguna vista;
- deja un diagnóstico reservado a la operadora.

Una nota **sin** clasificación sigue con la semántica heredada (SE-420): sin cambios ni migración.

## Requisitos

### R1 — Parser canónico único

`src/storage/note-level.ts` exporta `parseClassification(relPath, raw): ParsedClassification` con:

```ts
type ClassificationKind = 'ABSENT' | 'VALID' | 'INVALID' | 'UNPARSABLE' | 'UNKNOWN_LEVEL';
interface ParsedClassification { kind: ClassificationKind; level?: 'N1'|'N2'|'N3'|'N4'|'N4B'; diagnostic?: string }
```

Cada caso se clasifica así:

| Caso | Resultado |
|---|---|
| Sin frontmatter, o frontmatter válido sin la clave | `ABSENT` |
| Frontmatter que no parsea y menciona `confidentiality` (comparación textual sin distinguir mayúsculas) | `UNPARSABLE` |
| Frontmatter que no parsea y no menciona la clave | `ABSENT` (semántica heredada) |
| Valor que no es una cadena (lista, objeto, número) | `INVALID` |
| Cadena que no es `N1`..`N4`, `N4B` (sin distinguir mayúsculas; espacios recortados; también `N4b`) | `UNKNOWN_LEVEL` |
| Valor con caracteres de control, bidi o de anchura cero | `INVALID` |

`diagnostic` es un código estable sin contenido de la nota (p. ej. `yaml-unparsable`, `non-string`, `unknown-level`).

Todas las vistas usan esta función y ninguna otra: `VaultStorage`, la búsqueda BM25 por documento, el indexador y el servicio RAG, el grafo, los backlinks, query, list, stats y A2A. `noteLevel()` y `exceedsDomeLevel()` pasan a ser envoltorios de esta función o desaparecen.

### R2 — Cuarentena

- `fileOutOfLevel` y `contentOutOfLevel` devuelven «no servir» cuando el resultado es `UNPARSABLE`, `INVALID` o `UNKNOWN_LEVEL`, en cualquier cúpula y con cualquier nivel de cúpula.
- El indexador no indexa esas notas y las cuenta en el informe de sync como `quarantined`, con su código de diagnóstico.
- `vault_health` muestra el contador por código de diagnóstico, **sin rutas ni títulos**. Las rutas se ven solo por CLI local: `savia-vaults dome quarantine [--dome X]`.
- Escribir por `vault_write` una nota con clasificación explícita inválida se rechaza con un error claro antes de persistirla.

### R3 — Revalidación al servir en RAG

Antes de devolver cada hit, `RagService` revalida la nota de origen con `fileOutOfLevel`:

- se usa la caché por ruta, que está acotada;
- en la clave de la caché entran `mtimeMs`, `ctimeMs` y `size`.

Un hit cuya nota ya no existe, ha quedado fuera de nivel o está en cuarentena se descarta. El descarte se cuenta en `degradation`, sin revelar la ruta. `includeStale` **no** altera esta comprobación, porque solo gobierna la temporalidad.

### R4 — Tipos alineados

`Confidentiality` en `src/rag/types.ts` incluye `N4B`, con el mismo orden que en `note-level.ts`. Ningún otro nivel nuevo.

### R5 — Polaridad y códigos en BM25

- Se quitan de las stopwords `no`, `not`, `ni`, `sin` y `nada`.
- Se verifica que `nunca`, `salvo`, `excepto`, `prohibido` y `never` no están en la lista y que la normalización conserva identificadores con guiones y dígitos (`CT-2026-047`, `E-1047`): o como término completo, o con sus partes indexadas, y que la búsqueda exacta funciona.
- `BM25_VERSION` sube a `v2`, de modo que el índice BM25 se reconstruye sin reembeber.

### R6 — Corpus y baseline

- `eval/fixtures/`: conjuntos sintéticos públicos, sin datos reales:
  - `negation-polarity`, con pares casi idénticos que invierten el sentido;
  - `identifiers-exact`;
  - `malformed-meta`, que incluye el caso `confidentiality: [N4` en una cúpula N2.
- Antes y después del cambio se mide recall@10 y MRR sobre el banco de 36 consultas de `savia-docs` y se dejan las cifras en la PR.
- Si recall@10 o MRR caen más de 0,02, la PR queda en HOLD para la operadora, con la causa medida.

## Criterios de aceptación

- **AC-1:** una nota `confidentiality: [N4` en una cúpula N2 no aparece en `vault_read`, `vault_search`, `vault_rag`, `vault_list`, `vault_graph`, `vault_query`, backlinks, stats ni A2A. `vault_health` cuenta 1 en `yaml-unparsable`.
- **AC-2:** lo mismo con `confidentiality: N7`, `confidentiality: [N2]` y un valor con carácter de anchura cero.
- **AC-3:** una nota sin `confidentiality` se sirve igual que en main (test de regresión).
- **AC-4:** una nota indexada como N2 y reclasificada a N4 en disco desaparece de `vault_rag` **sin** sync, en la siguiente consulta. Una nota indexada y borrada, también.
- **AC-5:** `includeStale: true` no devuelve ninguna nota en cuarentena ni fuera de nivel.
- **AC-6:** `vault_write` rechaza una clasificación explícita inválida y no escribe nada.
- **AC-7:** la consulta BM25 «no está permitido conectar» puntúa por encima el fragmento con la negación que su gemelo sin ella. `E-1047` devuelve el documento exacto en primera posición.
- **AC-8:** baseline antes/después en la PR. Regresión de más de 0,02 en recall@10 o MRR, HOLD.
- **AC-9:** cada test de AC-1..AC-7 falla contra main.
- **AC-10:** el fuzz de frontmatter (≥200 casos generados con YAML inválido, Unicode, tipos mezclados) nunca produce `ABSENT` cuando el texto contiene una clave `confidentiality` con valor no canónico.

## Fuera de alcance

- Estados de admisión, ContextBundle, AEK: SE-482.
- Migración o reclasificación masiva de notas existentes.
- OCR, reranker y ANN.

## Rollback

Revert de la PR. El índice BM25 v2 se reconstruye solo a v1 al bajar la versión. La cuarentena no persiste estado propio: depende del contenido de la nota. Un revert **reabre** la exposición de notas mal clasificadas, así que antes de revertir hay que corregir esas notas (`dome quarantine` las lista).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Servidor MCP savia-vaults | `~/.claude.json` mcpServers (stdio) | `opencode.json` mcp (stdio), mismo binario |
| Lógica de clasificación | `projects/savia-vaults/src/storage/note-level.ts` | idéntica (mismo servidor) |

### Verification protocol

- [ ] Funciona en runtime OpenCode (mismo servidor MCP; sin código por frontend)
- [ ] Tests vitest cubren el servidor; los frontends solo lo consumen
- [ ] No añade hooks

### Portability classification

- [x] **PURE_BASH** (equivalente: lógica en el servidor MCP, independiente del frontend)
