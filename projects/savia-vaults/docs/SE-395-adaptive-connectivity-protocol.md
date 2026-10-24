# SE-395 — Protocolo preregistrado de conectividad adaptativa (R00 + R01)

> Estado: F0 y F1 entregadas. Ninguna fase adaptativa está implementada ni activada.
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
| Tokens recuperados / irrelevantes / útiles | 16 641 / 11 331 / 3 510 |
| Densidad de contexto útil | 0,211 |
| Provenance / exposición | 1,0 / 0 |

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
cambia sin regenerar.

## 7. Decisión de fase

F0 y F1: **GO** para continuar a F2 (guidance estático + shadow), condicionado a
revisión humana de este protocolo. No hay evidencia todavía de que un router
adaptativo mejore nada: el baseline ya tiene recall 0,92 con 2,8 llamadas
remotas por consulta, y esa es la única cifra que F2–F3 deben batir.
