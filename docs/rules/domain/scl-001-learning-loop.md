---
context_tier: L2
token_budget: 700
spec: SCL-001
---

# Savia Continuous Learning — bucle de aprendizaje (SCL-001)

> Política de operación del bucle de aprendizaje continuo de Savia. El sustrato
> de texto (CONSTITUCION + CRITERIO + memoria + skills) es el artefacto de
> despliegue que aprende. Cero fine-tuning, cero acoplamiento a proveedor.

## Paths canónicos

| Recurso | Path | Notas |
|---|---|---|
| Learning proposals (local) | `docs/learning-proposals/` | Artefacto markdown versionado (fuente local, CRIT-003) |
| **Cúpula SaviaLearning** | `vaults/SaviaLearning/learning/` | Persistencia cross-instancia (SCL-002). Git-backed, entidad `learning_proposal` en el grafo |
| Lifecycle ledger | `output/learning-loop/lifecycle.jsonl` | Transiciones de estado auditadas |
| Rollback ledger | `output/learning-loop/rollback.jsonl` | Reversiones con causa registrada |
| Graph index | `output/learning-loop/graph-index.jsonl` | Índice local (SCL-001); el grafo real vive en SaviaVaults |
| Hook de captura | `.claude/hooks/learning-capture-hook.sh` | PostToolUse Task. Master switch `SAVIA_LEARNING_CAPTURE=on\|off` (**default ON** — fix 2026-08-20: un bucle con switch off no aprende). Detecta errores verbalizados Y **desviaciones de norma** ("debi usar X", "en vez de usar Y", "canal equivocado"). Evidencia por hash de respuesta cuando no hay ficheros (SCL-001.1 D1). Nunca bloquea |

## Persistencia y federación (SCL-002)

- **Persistir**: `learning-proposal.sh --persist` (o `learning-persist.sh --file <p>`) escribe la lección en la cúpula `SaviaLearning` con frontmatter `entity.type: learning_proposal` + `relations` (PROPOSES_CHANGE, EVIDENCE_FROM, MEASURED_BY) + wikilinks → indexada en el grafo de SaviaVaults.
- **Consumir (cross-instancia)**: `learning-federate.sh --list` lista lecciones de la cúpula; `--import <id>` las trae como propuesta local `INFERRED` (shadow, sin efecto), pendiente de `human_authored`. NUNCA auto-activa (CRIT-031).
- **Federación cross-dome (SCL-007)**: `learning-federate.sh --share <id> --to <url>` envía la lección a otra instancia vía A2A `/share`; `--search-remote` consulta `/search`. La receptora importa como `INFERRED` (shadow), nunca auto-activa.
- **Auto-descubrimiento (SCL-009)**: `federation-discover.sh --check` registra las instancias del pool y actualiza su salud vía `/health`; `learning-federate.sh` sin `--url` usa la primera sana.
- **Reconciliación (SCL-010)**: `learning-reconcile.sh` detecta lecciones duplicadas/conflictivas entre instancias y las clasifica en el árbol 3-bucket (evolution|auto-resolve|conflict-doc); solo propone, no muta (CRIT-031).
- **SaviaVaults es el servidor; `example-context`, `savia-docs` y `SaviaLearning` son cúpulas.** Las lecciones de SCL van SOLO a `SaviaLearning`.

### Política de publicidad (CRIT-001, decisión 2026-08-21)

Este workspace es un repo **público** en `gonzalezpazmonica/pm-workspace`.
`docs/learning-proposals/` (fuente local versionada) es visible en el repo
público; `labs/` (experimentos) es gitignored y repo local **sin remote**.

**Regla**: en `docs/learning-proposals/` solo se publican LPs **sanitizadas** —
la lección genérica, sin datos del experimento (métricas, puntuaciones, modelo
de inferencia, run-XXX, nombres de línea de investigación). El detalle completo
vive en el vault `SaviaLearning` (privado) y en `labs/` (privado). El
`evidence_hash` apunta a evidencia sanitizada o se omite el path del run.

Antes de mergear una LP derivada de Savia Labs: verificar que NO contenga
paths de `labs/`, puntuaciones, modelo, ni datos del experimento. Decisión de
la operadora 2026-08-21: "solo LPs sanitizadas".

## Recall operativo (SCL-003 + SCL-005)

- **Recuperar en sombra**: `learning-recall.sh --query "<contexto>"` consulta SaviaLearning (BM25) y registra coincidencias sin influir. `INFERRED`, `proposed` y `canary` nunca emiten contexto.
- **Recall híbrido (SCL-005)**: `learning-recall.sh --hybrid` fusiona búsqueda léxica y semántica para encontrar sinónimos. El ranking híbrido pasa por el mismo filtro de autoridad; no eleva propuestas ni expone sus snippets.
- **Inyección autorizada**: `--mode effective` solo devuelve el `principio` de una entrada `CRIT-XXX` con `provenance: human_authored` cuando una propuesta `active/human_authored` la enlaza mediante `criterion_id`. El snippet de la propuesta nunca se inyecta.
- **Hook dual**: `.claude/hooks/learning-recall-hook.sh` sirve a Claude Code y OpenCode mediante `savia-gates`. Acepta `content` y `prompt_text`, emite JSON canónico y falla abierto en menos de 5s.
- **Métrica privada**: `output/learning-loop/recall.jsonl` guarda `query_hash` y contadores; nunca el prompt completo.

## Ciclo de vida del sustrato

```
proposed (shadow) → canary → active → superseded
```

- **shadow** (`provenance: INFERRED`): sin efecto en gates ni comportamiento.
- **canary**: sin efecto de recall hasta definir autoría humana verificable para el subconjunto.
- **active** (`provenance: human_authored`): solo influye si enlaza un criterio humano activo verificable.
- **superseded**: tombstone + cuarentena (CRIT-024). Nunca se borra.

## Mapeo de autonomía SCL ↔ Levels of AGI (política 2026-08-21)

Autorizado por la operadora (LP-20260821-71880b47, active). Detalle completo
en `labs/notebook/20260821-sagi-research-agi.md` (privado).

| SCL (Savia) | DeepMind autonomy | Gate |
|---|---|---|
| L0 draft | 1 Tool | sin ejecución autónoma |
| L1 report-only | 2 Consultant | reporta, no ejecuta |
| L2 assisted | 3 Collaborator | ejecuta asistido |
| L3 unattended | 4 Expert | ejecuta con supervisión |

**Límite deliberado**: el bucle SCL NO escala al nivel 5 (Agent, totalmente
autónomo) porque CRIT-031 prohíbe la auto-activación: solo la operadora activa
entradas al sustrato. Ese límite es alineación, no capacidad.

## Gates inmutables

1. **No auto-activación** (CRIT-031 / ART-11): `proposed→active` y `canary→active`
   REQUIEREN `--human-trailer`. Ninguna transición a `active` puede originarse en
   un agente. `learning-lifecycle.sh --strict` lo bloquea con exit 4.
2. **Promoción condicionada a métrica**: en `canary`, si `metric_after <
   metric_before` (regresión de `L`), la entrada NO asciende — se revierte a
   `proposed` con causa registrada (el "arreglé un bug y metí otro" detectado en
   canary).
3. **Rollback como comando auditable** (`learning-rollback.sh`): restaura el
   sustrato al estado previo vía git y registra motivo + p_consistent antes/después.
   Nunca es un `git revert` manual a ciegas.
4. **No-aprendizaje es resultado de primera clase**: el reporte de ventana con
   `ΔL ≤ 0` y 0 activaciones emite "Savia no aprendió esta ventana" (ART-04).

## Métrica L

```
L = w_p·p_consistent + w_d·(1 − divergencia) + w_i·ignorancia_resuelta
```

Pesos 0.5/0.3/0.2. Determinista y agnóstica a modelo (inputs escalares, nunca identidades de proveedor).

**Input SE-336 (S4)**: `turn-sdlc-report.sh` alimenta `divergencia` (SE-335 + DoD gate); si `pct_order_ok` no sube, se rediseña.

## Agnosticismo a LLM (construcción, no afirmación)

- El bucle solo lee sustrato (texto) y escribe propuestas (markdown/JSONL).
- `learning-guard.sh` verifica: 0 vendor names en el código del bucle, 0
  escrituras fuera del sustrato, CONSTITUCION invariante tras N ciclos.
- PURE_BASH: corre idéntico bajo cualquier frontend.

## Sustrato antes que LLM (LP-20260823-l11-run3)

Criterio/memoria inyectan el sustrato (recall CRITERIO + lessons) antes del
LLM; el modelo aislado no lo mantiene (SCL-011 `LEER → decidir`). Confirma P2/P3.

## Uso

```bash
# S1 — captura
bash scripts/learning-proposal.sh --origin "<origen>" \
  --evidence "ruta[:hash]" --diagnosis "<d>" --change "<c>" --target criterio
# S2 — ciclo de vida (humano activa)
bash scripts/learning-lifecycle.sh --file <proposal.md> --to canary --actor agente
bash scripts/learning-lifecycle.sh --file <proposal.md> --to active --actor operadora \
  --human-trailer <sig> --metric-before <L> --metric-after <L>
bash scripts/learning-rollback.sh --file <proposal.md> --reason "<motivo>"
# S3 — métrica y reporte
bash scripts/learning-metric.sh --p-consistent 0.8 --divergence 0.2 --ignorance-resolved 0.5
bash scripts/learning-report.sh --window W34 --captured N --activated M \
  --p-consistent-before X --p-consistent-after Y
# S4 — guard de agnosticismo
bash scripts/learning-guard.sh --loop-dir scripts/ [--expect-constitution-sha256 <hash previo a los ciclos>]
# SCL-004 — divergencia grafo-modelo (Labs L1)
bash scripts/learning-divergence.sh --claim "<declaracion>" --graph-query "<tema>" \
  --threshold 0.6 [--propose]
# SCL-006 — autonomía graduada por p_consistent
bash scripts/learning-autonomy.sh --p-consistent 0.8 --requested L2
#   p<0.5→L0 · 0.5-0.7→L1 · 0.7-0.85→L2 · ≥0.85→L3 (+historial+humano)
```

## Referencias

- Spec: `docs/specs/SCL-001-aprendizaje-continuo.spec.md`
- Roadmap: `docs/SCL-ROADMAP.md`
- Criterios: CRIT-002, CRIT-003, CRIT-019, CRIT-022, CRIT-024, CRIT-031; ART-01/04/05/11.
