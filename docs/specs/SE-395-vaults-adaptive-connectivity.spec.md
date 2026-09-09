---
status: APPROVED
approval: "Operadora 2026-09-09: aprobación global de trabajo pendiente"
priority: P1
developer_type: agent-team
created: 2026-09-07
parent: SE-280
related_specs: [SE-282, SE-309, SE-396]
risk: L2
type: research-and-experiment
implementation_model: gpt-5.6-luna
---

# SE-395 — Savia Vaults Adaptive Connectivity

## Estado y alcance

Propuesta reconciliada del diseño aportado por la operadora. Esta entrega sólo
persiste análisis y contrato; no implementa ni autoriza activación. ID comprobado
libre en specs locales y planning al redactar; no implica reserva remota.
Baseline inspeccionado: `0c7cd9d104134aab90d627bb9def38e2fd299d4d`.
Referencias inequívocas: `projects/savia-vaults/specs/SE-280-savia-vaults.spec.md`,
`SE-282-savia-federate.spec.md` y `SE-309-knowledge-governance.spec.md` en esa misma
carpeta. No confundir SE-309 con otra spec homónima del workspace.

Pregunta: ¿puede una topología de acceso adaptativa reducir coste y aumentar
contexto útil sin degradar recall, provenance, seguridad ni autoridad humana?
NO-GO es un resultado científico válido. Las mejoras propuestas no están medidas.

## Reconciliación con implementación

- `projects/savia-vaults/src/federation/search.ts`: búsqueda local y remotas
  saludables en paralelo; merge/dedup/cache existentes. Reutilizar, no duplicar.
- `src/federation/types.ts`: pesos, tags, salud y attribution existentes; no
  presupone un contrato completo de policy por consulta.
- `src/knowledge/{decision,decision-state,conflicts,provenance}.ts`: reutilizar
  decisiones, estados, conflictos y provenance; no crear otro knowledge graph.
- El cache observado no incorpora principal/policy/revisión de contenido en su
  clave; cache hit pierde `sources`. `maxTotalResults` no limita el resultado.
  Corregir/verificar en SE-396 antes de cualquier canary adaptativo.
- `src/server/mcp.ts`: selección de instancia por dome y uso de grafo global
  requieren prueba de aislamiento. Hallazgo estático, no filtración demostrada.
- Estados documentales PARTIAL/PROPOSED antiguos no prueban ausencia de código
  ni graduación operacional. Congelar inventario ejecutable en fase 0.

## Contrato no negociable

Policy se evalúa antes de selección observable, cache, scoring y traversal; se
reevalúa al ejecutar ante cambios de policy. DENY nunca es un peso negativo.
CAN_ROUTE != CAN_ACCESS != AUTHORITY. Popularidad, frecuencia, learned_weight y
success no son trust ni verdad. Conflictos permanecen hasta resolución gobernada.
No reescribir conocimiento, provenance, decision states, permisos o confidencialidad.
Prune route != delete knowledge. No secretos en cues, métricas ni receipts.
Producción conserva máximo un salto federado. Waypoints internos no autorizan
relay remoto; simulación multi-hop usa únicamente fixtures offline.
Fallo adaptativo vuelve a federación existente con policy y presupuesto restante;
si no puede garantizar ambos, termina sin expansión, no hace broadcast ilimitado.

## Modelo experimental

Router deterministic-first, sin LLM obligatorio: intent explícito, metadata,
BM25, relaciones existentes, freshness y utilidad observada. Embeddings sólo si
ya existen. Desempate estable por ID; reloj y semilla inyectables en benchmark.
Cues versionados: attracts/repels/specialties; schema acotado, finite scores,
límites de tamaño y rechazo de campos desconocidos. Metadata remota es no confiable.
Trust/confidentiality son referencias gobernadas, no autoafirmaciones del destino.

KnowledgeEdge: source/target, intents, configured_weight, learned_weight,
success/failure/useful/traversal counters, timestamps, state, evidenceRefs.
Estados DISCOVERY/ACTIVE/WEAK/DORMANT/BLOCKED; BLOCKED sólo por policy autorizada.
Learned weight acotado inicialmente a 0.30, separado de peso configurado; nunca
reactiva BLOCKED. Decay sólo de evidencia operacional, no de autoridad/trust.
Pruning ACTIVE→WEAK→DORMANT conserva historia y es dry-run por defecto.

PioneerRoute guarda conectividad útil, no respuestas. KnowledgeTract añade
intentPattern, orderedTargets, uses, successRate, evidenceRefs y estados
CANDIDATE/CALIBRATING/STABLE/DEGRADED/DORMANT. STABLE requiere calidad verificada
en holdout y diversidad de casos, no sólo usos; tampoco significa TRUSTED.
Invalidar ante cambios de policy, trust, confidencialidad, targets, contenido,
conflictos o versión del router. Claves incluyen revisiones relevantes.

Branch por evidencia insuficiente, conflicto, consulta multidominio, provenance
faltante o mandato de segunda fuente; suficiencia usa reglas congeladas y
evidencia independiente, no confianza autorreportada de un LLM.
Reforzar utilidad verificada, no consulta/citación por sí sola; feedback no
autenticado no actualiza pesos. Conflicto encontrado no es fallo de ruta.
Homeostasis mide concentración/diversidad/utilidad normalizada por exposición;
explora sólo alternativas autorizadas, sin desplazar fuentes obligatorias.
Lifecycle de nuevo vault DISCOVERY/CALIBRATING/STABLE separado del trust.
Controller propone ajustes/poda/orphans/ciclos; nunca modifica policy.

## Configuración y almacenamiento

Flags adaptive, pioneer, plasticity y exploration: false. Nunca activar al merge.
Perfil de benchmark inicial: maxVaults=3, maxRemoteCalls=3, maxBranches=2,
maxLatencyMs=3000, maxContextTokens=4096; definir branches como destinos adicionales
al primario. Producción maxHops=1; simulación maxHops=3. Exploración futura 0.05,
desactivada; budgets cuentan intentos, retries y fallback conjuntamente.
Terminations: ANSWER_SUFFICIENT/BUDGET_EXHAUSTED/POLICY_BLOCK/NO_ROUTE/CONFLICT/
TIMEOUT/UNKNOWN. Cancelar trabajo pendiente al vencer presupuesto.
Reutilizar storage local existente: grafo gobernado versionable separado de
telemetría agregada; no commit por lookup. Si exige nuevo storage, human gate.
Desactivar flag restaura baseline sin migración destructiva ni learned influence.

## Experimentos y medición preregistrada

F0 inventario + research note: patrón biológico → abstracción y límites. La
analogía no está validada científicamente en esta entrega; contrastar fuentes
primarias antes de atribuir mecanismos. No afirmar equivalencia cerebral.
F1 baseline reproducible; F2 static guidance + shadow; F3 A/B independiente;
F4 pioneer + branching; F5 bounded learning; F6 pruning/homeostasis/critical period;
F7 simulación multi-hop. Cada fase termina GO/NO-GO/NEEDS_MORE_EVIDENCE.
No avanzar por el mero hecho de haber implementado la anterior.

Dataset inicial mínimo 180 consultas, ≥20 por estrato: monodominio, cross-domain,
ambiguas, conflictivas, stale, restringidas, unhealthy, repetidas, nuevas.
Añadir casos donde baseline gana y casos realistas sanitizados autorizados;
fixtures favorables exclusivamente no bastan. Separar train/calibration/test por
familia de intención; congelar hash, etiquetas y umbrales antes del test final.
Relevancia, utilidad y provenance etiquetadas independientemente del router.
Comparar mismo snapshot, k, tokenizer y condiciones cold/warm cache. Registrar
recall@k, precision@k, MRR/NDCG, consultas/intentos, llamadas remotas, p50/p95,
tokens, duplicados, conflictos y useful_context_tokens/retrieved_context_tokens.
Denominador cero: N/A, no mejora ficticia. No mezclar tokens reales y proxies.

Gate propuesto: ≥30% menos consultas remotas, ≥25% menos contexto irrelevante,
recall delta ≥−0.02 absoluto, provenance ≥baseline, cero bypass/exposición,
p95 ≤baseline y useful-context-density ≥1.20×baseline. Usar intervalo pareado
95% para recall no inferior; muestra insuficiente → NEEDS_MORE_EVIDENCE.
Documentar cualquier cambio de protocolo antes de consultar holdout.
Shadow ejecuta sólo baseline: selección y coste contrafactual son estimaciones,
no ahorro/latencia challenger demostrados. A/B real usa transporte local aislado
y corpus congelado; canary con destinos reales requiere autorización aplicable.

## Seguridad, explicabilidad y evidencia

Suite adversarial: specialty=everything; trust bajo/peso alto; metadata falsa;
BLOCKED con successes históricos; query sensible; ciclo; branch explosion;
empates; ruta stale; conflicto oculto; popularity attack; unhealthy dominante;
tags envenenados; elevación de confidencialidad; retrieval jamás utilizado.
Además: aislamiento entre principales/domes en cache/grafo, cambio de policy
entre selección y ejecución, fallos/timeouts y fallback con presupuesto agotado.
Probar invariantes de autoridad, one-hop, provenance, apagado y no borrado.

Receipt versionado, integrado con evidencia existente: opaque query_id, versión,
config/dataset hashes, visited/skipped/reasons autorizados, presupuesto consumido,
terminación, fuente original y tipo de evidencia. Hash de query NO anonimiza;
preferir ID opaco, o HMAC mediante mecanismo existente aprobado. Nunca credenciales,
query íntegra o nombres de vaults prohibidos en explicaciones al llamante.
Métricas sin labels de alta cardinalidad ni contenido. Explain determinista
"why this/why not" sujeto a permisos; inspección CLI es adaptador, no core.
Prune CLI sólo dry-run; simulador incapaz de abrir red.

## Acceptance y handoff Luna

AC01–06: baseline/schema/policy-before-score/attraction-repulsion/subset/fallback.
AC07–12: pioneer auditable sin respuesta obligatoria/pesos separados/no elevación/
no borrado/dormancy con provenance. AC13–16: budgets/one-hop/receipts/explain.
AC17–20: A/B reproducible/coste+calidad/adversarial/apagado sin regresión.
Cada AC debe tener test y receipt; fases diferidas no se marcan PASS anticipadamente.
Research DoD: F0–F3, dataset congelado, tests, benchmark, recomendación y revisión
humana. Full experimental DoD añade F4–F7 y justificación complejidad/valor.
Estado permanece PROPOSED; consultar lifecycle canónico antes de iniciar código.
Paquete: SHA, timestamp, config, dataset hash, outputs sanitizados, métricas,
distribuciones, receipts, tests, limitaciones y decisión humana.

Luna ejecutará slices y gates de `SE-395-396-luna-roadmap.md`, WIP=1. Decisiones
no determinadas, nuevo storage/cloud/LLM obligatorio, cambio de autoridad/trust,
default-on, multihop real o efectos externos → NEEDS_HUMAN_DECISION.
