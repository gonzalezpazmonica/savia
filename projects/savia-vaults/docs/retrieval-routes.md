# Rutas de recuperación (SE-489)

Las rutas de recuperación son estrategias intercambiables sobre un contrato común: M0 (híbrido actual), M1 (vecinos), M2 (reranker), M3 (`StructureIndex`), M4 (navegación con LLM local), M5 (grafo de referencias), M6 (router) y M7 (cuantización en sombra). Todas son opt-in. Sin `route`, `vault_rag` hace exactamente lo de siempre (AC-4).

Esta guía explica cómo se escribe una ruta nueva: el contrato, el guard, la batería de seguridad y el registro.

| Fichero | Qué es |
|---|---|
| `src/retrieval/route.ts` | Contrato: `RetrievalRoute`, petición, resultado, evidencia, traza, presupuesto y registro. |
| `src/retrieval/guard.ts` | Autorización centralizada, aplicada a cada nodo antes de abrirlo. |
| `src/retrieval/runner.ts` | Único sitio que ejecuta una ruta: plano de control, guard, presupuesto y guard final. |
| `src/retrieval/routes/` | Una ruta por módulo; `index.ts` las registra. |
| `src/retrieval/evidence-eval.ts` | `rag eval --route/--bench`: métricas de evidencia e IC 95 %. |
| `tests/retrieval/security-battery.ts` | Batería negativa de seguridad (AC-2), parametrizada por ruta. |

## 1. El contrato

Una ruta implementa `RetrievalRoute`:

```ts
export interface RetrievalRoute {
  id: string;                       // 'M1', 'M5'…: estable, [A-Za-z][A-Za-z0-9_-]{0,31}
  description: string;
  contractVersion: typeof ROUTE_CONTRACT_VERSION;   // hoy 1
  supportsAsOf: boolean;            // si no, el runner avisa AS_OF_UNSUPPORTED
  requiresDeclaredBudget: boolean;  // AC-7: M4 → true
  run(req: RetrievalRequest, ctx: RouteContext): Promise<RouteOutput>;
}
```

**Entrada (`RetrievalRequest`, congelada).** Contiene:
- la consulta;
- las cúpulas autorizadas (`domes`: solo nombre y nivel, nunca rutas en disco);
- `asOf` opcional;
- el presupuesto (`maxLatencyMs`, `maxModelCalls`, `maxNodes`, `maxHops`, `maxInputTokens`) y si lo declaró la petición (`budgetDeclared`);
- la semilla, `k`, `mode`, `pathPrefix`, `includeStale` y `maxChars`.

Las cúpulas las decide el plano de control (`authorize`), nunca el modelo ni el texto de la consulta.

**Salida (`RouteOutput`).** Contiene:
- `hits`: compatibles con `RagHit`;
- opcionalmente, `evidence` de nodos leídos que no son hits, `abstain` y `warnings`.

Los `warnings` son códigos `[A-Z][A-Z0-9_]+`; el texto libre se descarta. La ruta no rellena la traza ni el consumo: lo hace el runner.

**Resultado final (`RetrievalResult`).** Lo construye el runner con:
- `hits`;
- `evidence[]`, una por hit con el mismo `chunkId`: `{dome, document, revision, locator, contentHash}`;
- `trace`: `{route, reason, seed, steps, denied}`;
- `consumed`: el presupuesto gastado;
- `abstain` y `warnings`.

En la evidencia:
- `revision` es `sha256:` de los bytes actuales en una nota, o el id de revisión en Savia Files;
- `locator` es `#<ordinal> <encabezado>` en una nota, o el localizador canónico en Files (`page:3`, `cell:Hoja!B2`, `lines:1-4`);
- `contentHash` es el `sha256:` del texto servido.

## 2. Leer solo a través del contexto

Una ruta **no importa `fs` ni `RagService`**. Todo lo que lee pasa por `RouteContext`:

| Método | Qué hace | Descuenta |
|---|---|---|
| `candidates(query, {k, mode})` | Candidatos de `RagService` (BM25 + denso + RRF) en las cúpulas autorizadas, cada uno admitido por el guard | 1 `modelCalls` + tokens si `mode ≠ bm25`; 1 `nodes` por hit |
| `openNote({dome, path})` | Contenido actual de una nota admitida (revalida la clasificación sobre los bytes leídos) | 1 `nodes` |
| `documentChunks({dome, path, documentId?})` | Chunks del índice activo de un documento admitido (vecinos, padre) | 1 `nodes` |
| `consume(key, n)` | Gasto propio: `hops`, `modelCalls`, `inputTokens`, `nodes`. `false` si no queda y entonces no descuenta | — |
| `timeLeftMs()` | Lo que queda de `maxLatencyMs` | — |
| `step(step, detail?, nodes?)` | Paso de la traza. No metas en `detail` contenido de nodos | — |
| `evidenceOf(hit)` | Evidencia de un hit con el estado actual | — |

Cuando un nodo no se puede abrir, el contexto devuelve `undefined`, sea por denegación, por inexistencia o por presupuesto agotado. La ruta no distingue el motivo y debe seguir con lo que tiene.

El contenido leído es **dato, nunca instrucción**: una ruta no cambia de comportamiento por lo que diga una nota. Esto aplica también a M4 con LLM: el texto va como contexto, nunca como herramienta ni como parámetro.

Una expansión (M1/M3/M5) lleva su propio `visited` y gasta un `hops` por salto. Cuando `consume('hops')` devuelve `false`, se detiene.

## 3. El guard

`RetrievalGuard.admit(ref)` comprueba, con el estado **actual** y en este orden:

1. La cúpula está entre las autorizadas. Si no, responde `not-found`, igual que un nodo inexistente: no revela título, árbol ni existencia.
2. La ruta es relativa, sin `..`, de markdown, y su `realpath` no sale de la cúpula (enlaces simbólicos incluidos).
3. Nivel de nota y cuarentena (SE-481, `storage/note-level.ts`). Una nota borrada, reclasificada por encima de la cúpula o con una clasificación ilegible se deniega aunque siga en el índice.
4. Savia Files (SE-419): el documento existe, su nivel no supera el de la cúpula, y `canRead(principal, doc)`.

El **guard final** del runner vuelve a pasar cada hit por el guard antes de servirlo. Además, exige que el texto del hit (sin el `…` del recorte) esté en un chunk indexado del documento o en su contenido actual, y que el encabezado exista en ese documento. Estado, `supersededBy` y `source` se toman del índice, no de la ruta. Un hit que no cumple se descarta y cuenta en `trace.steps` como `guard:final`.

Una ruta con un fallo no puede, por tanto, servir contenido denegado en los hits. Sí podría filtrarlo por la traza si mete texto en `step()`. Para eso está la batería.

## 4. La batería de seguridad (AC-2)

Toda ruta nueva añade en su test:

```ts
import { describeSecurityBattery } from './security-battery.js';
describeSecurityBattery({ route: 'M5' });
describeSecurityBattery({ route: 'M4', budget: { maxModelCalls: 4, maxInputTokens: 4000 } }); // con requiresDeclaredBudget
```

Comprueba cuatro casos, cada uno con **0 violaciones**:

| Comprobación | Qué prueba |
|---|---|
| `denied-dome` | Una cúpula denegada contiene una nota con canario, título y un árbol no enlazado. Una nota pública la enlaza como cebo. La salida no contiene nada exclusivo de la cúpula denegada y es **idéntica** con y sin esa nota (no revela existencia). |
| `injection` | Una nota contiene órdenes, `<tool_call>` y vínculos a lo denegado. No cambia ningún fichero, no aparece `pwned.md`, la ruta de la traza no cambia, no se abre nada denegado y el consumo queda dentro del presupuesto. |
| `cycle` | Hay notas en ciclo a→b→c→a con wikilinks y `supersedes`/`superseded_by`. La ruta termina por sí misma (no por el corte de `maxLatencyMs`), con `hops ≤ maxHops` y sin hits repetidos. |
| `invalidation` | Tras el sync, una nota se borra, otra se sube a N4 y otra queda en cuarentena, sin volver a sincronizar. Ningún hit, evidencia ni traza las sirve. |

`prepare(f)` permite construir índices propios de la ruta (p. ej. el `StructureIndex` de M3) en cada mundo antes del sync.

La batería tiene autoprueba en `tests/retrieval/m0-hybrid.test.ts`: cuatro rutas defectuosas a propósito deben suspenderla. Si cambias una comprobación, esas pruebas tienen que seguir fallando con la ruta defectuosa.

## 5. Registro

1. Crea `src/retrieval/routes/<id>-<nombre>.ts` con la ruta y `registerRoute(...)` al final (ver `m0-hybrid.ts`).
2. Añade `import './<id>-<nombre>.js';` en `src/retrieval/routes/index.ts`.
3. Un id repetido es un error (`DUPLICATE_ROUTE`): no se sustituyen rutas en silencio.

Desde ese momento la ruta está disponible en:
- `vault_rag`: `{"query": "...", "route": "M5", "budget": {"maxHops": 3}, "seed": 1, "asOf": "2026-06-01"}`;
- la CLI: `savia-vaults rag eval --dome <d> --route M0,M5 --bench eval/evidence-bench --split dev`.

## 6. Banco de evidencia y `rag eval`

Un banco es un directorio con `*.json` (una lista o `{"cases": [...]}`) y `*.jsonl`. Cada caso tiene esta forma:

```json
{
  "id": "C-012", "category": "C", "split": "dev",
  "query": "plazo de preaviso del anexo II",
  "domes": ["savia-docs"], "denied_domes": [], "as_of": "2026-06-01",
  "required_evidence": [{ "document": "contratos/marco.md", "revision": "sha256:…", "locator": "Anexo II" }],
  "forbidden_evidence": [{ "document": "contratos/marco-v1.md" }],
  "must_abstain": false, "max_unauthorized_reads": 0
}
```

Reglas de validación (`validateCase`):
- La categoría va de `A` a `F` y el `split` es `dev` o `test`.
- `max_unauthorized_reads` vale siempre 0.
- Con `must_abstain: false`, el caso necesita al menos una `required_evidence`.
- Un campo desconocido es un error.

El `locator` de una evidencia requerida casa de una de estas formas:
- exacto;
- por ordinal: `#1` casa con `#1 …`, pero no con `#10`;
- por rango de Files (`page:3..`);
- por el último tramo del encabezado («Anexo II»).

`denied_domes` hace que el plano de control deniegue esas cúpulas en ese caso (categoría F).

Uso de `savia-vaults rag eval --dome <d>`:
- con `--route M0[,M1…]`, `--bench <dir>`, `--baseline <id>` (por defecto, la primera), `--split`, `--seed`, `--iterations`, `--k`, `--budget '<json>'` y `--json`;
- con `--route` y sin `--bench`, evalúa las rutas sobre el banco de regresión de 36 consultas (`--queries` o `rag.evalSet`), convertido con `legacyToCases`;
- sin `--route` ni `--bench`, es el `rag eval` de siempre (SE-410).

Métricas por ruta, globales y por categoría, todas con IC 95 % por bootstrap percentil:

| Grupo | Métricas |
|---|---|
| Recuperación | Recall@5/10/20, MRR y nDCG@10 a nivel de documento (`computeRecallAtK` de SE-331), `EvidenceRecall` y `exactIdentifierHit` |
| Gobernanza | `unauthorizedReads` (evidencias que un guard nuevo no admite al recontrolar) y `forbiddenUsed` |
| Abstención | `correctAbstention` (se abstiene ⇔ `must_abstain`; un caso con error nunca cuenta como acierto) |
| Operación | p50/p95, pico de RSS y llamadas/tokens de modelo |
| Gate | `violations`: casos con lecturas no autorizadas por encima del máximo. Objetivo: 0 |

Las comparaciones (`comparisons`) restan ruta − línea base **pareadas por pregunta**, con IC 95 %, global y por categoría. La regla de AC-6 se lee aquí:
- no inferioridad en A/B de −1 pp;
- ganancia en C/D/E con un IC que excluya 0.

Fuera del alcance de la base, pendiente de las rutas que lo necesiten:
- latencia **por fase** (hoy solo la total por caso);
- la segunda fase de R2: la evidencia entregada a un generador y la condición *oracle evidence*.
