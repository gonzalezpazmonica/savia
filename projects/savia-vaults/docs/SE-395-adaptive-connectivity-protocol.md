# SE-395 — Protocolo preregistrado de conectividad adaptativa (R00–R04)

> Estado: F0–F3 entregadas como código de medida. El router existe como módulo puro pero no está conectado a `FederatedSearchEngine` ni activado.
> Spec: `docs/specs/SE-395-vaults-adaptive-connectivity.spec.md`. Los flags
> `adaptive`, `pioneer`, `plasticity` y `exploration` siguen en `false`.

## 1. Inventario ejecutable (F0)

| Pieza | Estado verificado en código | Consecuencia para SE-395 |
|---|---|---|
| `src/federation/search.ts` | Local + remotos sanos en paralelo; merge round-robin por peso; dedup por hash de contenido; cache LRU | Es el baseline. No se duplica. |
| `src/federation/cache.ts` | Clave = consulta + domes + `maxResults` + principal + `policyRevision` + `contentRevision`; hit conserva `sources` | V02 ya cerró el hallazgo de aislamiento de cache. |
| `src/federation/types.ts` | `FederatedSearchContext` con `allowedDomeIds`; `weight`, `tags`, `status` por dome | La policy de acceso ya se aplica antes de cache y llamadas remotas. |
| `src/server/mcp.ts`, `registry/domes.ts` | Motor de conocimiento por dome (V01) | Aislamiento por dome ya probado en `tests/e2e/mcp-dome-isolation.test.ts`. |
| `src/knowledge/{decision,decision-state,conflicts,provenance}.ts` | Existen | Se reutilizan; no se crea otro grafo de conocimiento. |
| Router adaptativo, cues, pioneer, plasticidad | No existen | Fuera de F0/F1. |

Cambio de código en esta entrega: `FederatedSearchEngine` acepta `opts.client`
(por defecto `A2AClient`, comportamiento idéntico) para poder medir el baseline
sin abrir red.

## 2. Nota de investigación: del patrón biológico a la abstracción

La analogía (rutas con refuerzo y poda, circuitos pioneros, periodos críticos)
**no está validada científicamente en esta entrega**: no se contrastaron fuentes
primarias y no se afirma ninguna equivalencia con mecanismos cerebrales. Lo que
se toma es la abstracción de ingeniería, y solo eso se evalúa:

| Metáfora | Abstracción medible | Límite |
|---|---|---|
| Atracción/repulsión | Cues versionados que puntúan destinos tras la policy | `DENY` nunca es un peso negativo |
| Ruta pionera | Conectividad útil cacheada, no respuestas | Se invalida ante cambios de policy/trust/contenido |
| Plasticidad | Peso aprendido acotado a 0,30, separado del configurado | No reactiva `BLOCKED`; no es trust |
| Poda | `ACTIVE→WEAK→DORMANT`, dry-run | Podar una ruta no borra conocimiento |

## 3. Contrato preregistrado (congelado antes de cualquier holdout)

- Perfil: `k=10`, `maxVaults=3`, `maxRemoteCalls=3`, `maxBranches=2`,
  `maxLatencyMs=3000`, `maxContextTokens=4096`; tokenizador proxy por espacios
  (no se mezclan tokens reales y proxies).
- Gate (SE-395): ≥30 % menos consultas remotas, ≥25 % menos contexto
  irrelevante, delta de recall ≥ −0,02 absoluto (intervalo pareado 95 %),
  provenance ≥ baseline, exposición 0, p95 ≤ baseline, densidad de contexto útil
  ≥ 1,20× baseline. Muestra insuficiente → `NEEDS_MORE_EVIDENCE`.
- Los umbrales viven en `GATE_THRESHOLDS` y su valor entra en `freeze.json`.
  Cambiarlos tras consultar el holdout invalida esa evaluación y exige un
  holdout nuevo.
- Denominador cero se informa como `null` (N/A), nunca como mejora.

## 4. Dataset (180 consultas, 9 estratos × 20)

Estratos: monodomain, cross_domain, ambiguous, conflicting, stale, restricted,
unhealthy, repeated, new. Generado de forma determinista (`seed=395`) por
`src/federation/benchmark/generate.ts`; las etiquetas `relevant`, `useful` y
`forbidden` salen de la construcción del corpus, no de ningún router.

Split por familia de intención (tópico), estratificado por rol: dominios 0–1 →
train (90), dominio 2 → calibration (45), dominio 3 → test (45). Cada estrato
tiene consultas en los tres splits. Incluye `baselineAdvantage` (casos donde el
baseline ya es óptimo) y documentos prohibidos en `restricted`.

**Limitaciones declaradas**

- Corpus sintético: un resultado favorable aquí no demuestra utilidad operativa.
- Casos realistas sanitizados: **no incluidos**; requieren autorización
  aplicable y revisión de confidencialidad. Siguen pendientes.
- El estrato `repeated` repite el texto de `monodomain` variante 0; la
  repetición se ejerce además con la medición cold/warm.
- `duplicates` vale 0: el corpus no contiene contenido idéntico entre vaults.
- Provenance: el cliente simulado asigna `source` por vault, así que vale 1 por
  construcción. Solo detecta que el motor reescriba `source`; no mide atribución
  de un router futuro. No usarla como evidencia de mejora.
- Potencia estadística baja: calibration y test tienen una familia por estrato
  (5 consultas). Los intervalos serán anchos; cualquier gate de F2/F3 debe
  tratarlo y ampliar muestra antes de decidir.
- `new` es idéntico a `monodomain` (sin documentos ni vaults recién añadidos) y
  `ambiguous` reutiliza anclas de otro tópico (dominios 2↔3), con fuga menor de
  familia entre calibration y test. `baselineAdvantage` se asigna por dominio,
  no por resultado medido. Se corrigen al ampliar el dataset (cambio de protocolo).
- Latencias remotas: valores fijos derivados de un hash, no medidas.
- Etiquetas generadas por construcción, no revisadas por una persona
  independiente: la revisión humana de etiquetas queda pendiente.

## 5. Baseline reproducible (F1)

`FederatedSearchEngine` real, índice BM25 léxico por vault, cliente remoto
simulado (sin red), misma policy, `k` y tokenizador. Cada consulta se ejecuta
cold (motor nuevo) y warm (segunda llamada, cache).

| Métrica (cold, 180 consultas) | Valor |
|---|---|
| recall@10 | 0,921 |
| precision@10 | 0,503 |
| MRR / NDCG@10 | 0,883 / 0,839 |
| Llamadas remotas | 505 (warm: 0) |
| Latencia p50 / p95 (fixture) | 162 / 195 ms |
| Tokens recuperados / irrelevantes / útiles | 13 239 / 8 063 / 3 416 |
| Densidad de contexto útil | 0,258 |
| Provenance / exposición | 1,0 / 0 (provenance no informativa, ver límites) |

Conjunto evaluado: el top-k (k=10) que recibe el consumidor; ranking y tokens
se calculan sobre el mismo conjunto. Latencia cold: la mayor de las llamadas
remotas (paralelas) de la consulta; warm: lo que informa el motor en un cache
hit (`totalMs`), medido y no fijado. Los tests demuestran que ambas métricas
pueden fallar (cache desactivado, `source` falsificado).

Desglose por estrato y split en `eval/adaptive/baseline.json`.

## 6. Reproducir y congelar

```bash
cd projects/savia-vaults
npx tsx src/federation/benchmark/run.ts          # compara con eval/adaptive/, falla si hay deriva
npx tsx src/federation/benchmark/run.ts --write  # regenera (cambio de protocolo: documentarlo antes)
npx vitest run tests/unit/federation/benchmark.test.ts
```

`eval/adaptive/freeze.json` fija los SHA-256 de corpus, dataset y baseline más
el perfil y los umbrales; el test de artefactos congelados falla si cualquiera
cambia sin regenerar. El hash de `GATE_THRESHOLDS` está además fijado en el test
(`umbrales preregistrados`): cambiar un umbral exige tocar ese test, visible en
la revisión del diff; regenerar `freeze.json` no basta.

## 7. Decisión de fase

F0 y F1: **NEEDS_MORE_EVIDENCE** para F2. La infraestructura de medida está
entregada, pero el dataset es 100 % sintético, faltan los casos realistas
sanitizados autorizados que exige la spec («fixtures favorables exclusivamente
no bastan») y las etiquetas no tienen revisión humana independiente. F2 puede
prepararse en rama, pero no se declara GO hasta cerrar esas dos condiciones. No hay evidencia todavía de que un router
adaptativo mejore nada: el baseline ya tiene recall 0,92 con 2,8 llamadas
remotas por consulta, y esa es la única cifra que F2–F3 deben batir.

## 8. R02 — guidance y selección determinista

`src/federation/adaptive/guidance.ts` (schema v1: `attracts`/`repels` con score finito en [0,1], `specialties`;
rechaza campos desconocidos, listas largas, duplicados y versión distinta) y `select.ts`
(`selectDestinations`, función pura). Orden fijo: policy → salud → score → presupuesto. Un destino denegado
no se puntúa ni se nombra en el resultado (solo `deniedCount`). La repulsión baja prioridad pero no deniega.
`local` autorizado se incluye siempre y cuenta en `maxVaults`. Desempate por id. Con `adaptive=false` devuelve
exactamente el baseline. Guidance inválida → federación existente limitada al presupuesto restante
(`mode: 'fallback'`), nunca broadcast; sin presupuesto → `BUDGET_EXHAUSTED` sin expansión.

## 9. R03 — shadow

`runShadow` invoca el baseline exactamente una vez y calcula la selección del challenger sin red.
El receipt (`counterfactual-estimate`) lleva `queryId` aportado por el llamante (solo se valida formato y que no contenga la consulta; que sea opaco —UUID/aleatorio— es responsabilidad del llamante), hash de
configuración, destinos visitados/omitidos autorizados y la estimación de llamadas ahorradas y de resultados
del baseline que vendrían de destinos omitidos. Es una estimación, no ahorro demostrado. No incluye la consulta.

## 10. R04 — A/B aislado y decisión

`benchmark/ab.ts` ejecuta baseline y challenger sobre el mismo snapshot sin red (`ab-run.ts [split]`). La guidance
estática sale solo del split `train`; el router solo recibe consulta, policy y salud (sin etiquetas). Reglas de
decisión añadidas **antes** de ejecutar el holdout y separadas de `GATE_THRESHOLDS`: ≥100 pares para GO o NO_GO por
gates; exposición > 0 es NO_GO con cualquier muestra; bootstrap pareado seed 395, 2000 remuestreos, IC 95 %.

Resultado (una sola ejecución del holdout `test`, 45 pares, sin ajustes posteriores):

| Gate | Calibration | Test | Umbral |
|---|---|---|---|
| Reducción de llamadas remotas | 0,28 | 0,28 | ≥ 0,30 |
| Reducción de contexto irrelevante | 0,196 | 0,244 | ≥ 0,25 |
| Recall delta (cota inferior IC) | −0,129 | −0,800 | ≥ −0,02 |
| Provenance / exposición / p95 | pasa | pasa | — |
| Densidad de contexto útil | 1,05× | 0,43× | ≥ 1,20× |

Decisión formal: **NEEDS_MORE_EVIDENCE** (45 < 100 pares). Lectura honesta: en test el recall medio cae 0,69 y el
IC 95 % (−0,80 a −0,57) queda muy por debajo de −0,02; con los datos actuales este challenger estático **no es
defendible** y la recomendación es NO-GO para esa variante. Causa: la guidance de train no conoce los tópicos
nuevos de test (anclas inéditas y vault de origen distinto), así que el presupuesto recorta el vault de menor peso
por defecto. No se cambió ninguna regla ni umbral tras ver el holdout; ampliar a ≥100 pares o proponer otro
challenger exige un holdout nuevo.

## 11. Estado de AC

AC01–AC06 (schema, policy antes de score, atracción/repulsión, subconjunto, fallback): cubiertos por
`adaptive-select.test.ts`. AC13 (presupuestos) y AC14 (un salto: solo destinos registrados) en `select`.
AC15 (receipts) parcial: receipt de shadow, sin integración con el store de evidencia existente. AC16 (explain
"why this/why not") **no hecho**. AC17–AC20: A/B reproducible, coste+calidad y adversarial hechos; apagado =
baseline probado en benchmark. AC07–AC12 (pioneer, pesos aprendidos, dormancy) **diferidos**: R04 no justifica GO.

> Integración futura: en el benchmark `route` sustituye a la policy a propósito (para medir exposición). En producción la salida del router DEBE intersectarse con `allowedDomeIds`.
