---
id: SE-397
status: APPROVED
priority: P0
developer_type: agent-team
created: 2026-09-08
approved: 2026-09-08
approved_by: human-operator
related_specs:
  - SE-037
  - SE-280
  - SE-282
  - SE-309
  - SE-378
  - SE-388
  - SE-390
  - SE-391
  - SE-393
  - SE-394
  - SE-395
  - SE-396
risk: L2
type: architectural-evolution
working_title: Savia Self-Knowledge and Operational Excellence
execution_scope: F0_ONLY_PENDING_HUMAN_REVIEW
---

# SE-397 — Savia Architectural Self-Knowledge & Operational Excellence

## 1. Visión

Savia ha alcanzado un punto de madurez en el que el siguiente salto no debe
venir principalmente de añadir más comandos, agentes, skills, hooks o
abstracciones. Debe venir de comprender y gobernar mejor el sistema existente.

La siguiente evolución es que Savia pueda responder con evidencia:

- qué es y de qué está formada;
- qué fundamentos la gobiernan y qué puede hacer;
- cómo fluye una intención y dónde se decide autoridad;
- dónde se ejecuta y qué datos atraviesan cada frontera;
- qué evidencia se produce y qué depende de qué;
- qué cambia según frontend, provider, modelo o dominio;
- qué ocurre cuando falla un componente;
- qué está verificado y qué solo declarado;
- qué mecanismos cuestan demasiado o se solapan;
- qué partes están degradadas;
- qué impacto puede tener un cambio antes de ejecutarlo.

```text
CAPABILITY-AWARE SAVIA
        ↓
ARCHITECTURE-AWARE SAVIA
        ↓
OPERATIONALLY SELF-OBSERVING SAVIA
        ↓
SELF-GOVERNING COMPLEXITY
```

No significa autoconsciencia humana. Significa `ARCHITECTURAL SELF-KNOWLEDGE`:
un modelo explícito, verificable, versionado, consultable y conectado con la
realidad operacional.

## 2. Problema

El conocimiento arquitectónico está distribuido entre README, CLAUDE.md,
AGENTS.md, specs, rules, código, hooks, agents, skills, commands, `.scm`,
Vaults, documentación, receipts, evals, planning, adaptadores y runtime.

```text
RECONSTRUCTABLE ARCHITECTURE != EXPLICIT ARCHITECTURE MODEL
CAPABILITY GROWTH > SYSTEM UNDERSTANDING
LOCAL CORRECTNESS != SYSTEMIC QUALITY
```

`.scm` responde principalmente «¿qué puede hacer Savia?», pero no de forma
integral cómo está construida, dónde viven authority y trust, qué mecanismo es
fuente de verdad, qué depende de cada frontend o qué rutas carecen de evidencia.

## 3. Objetivo

Crear una capa fundacional que permita modelar la arquitectura; conectarla con
capabilities, runtime, authority y evidence; detectar drift; analizar impacto;
medir coste; comprender fallos; gobernar complejidad; reducir trabajo mecánico
sin reducir gobernanza; graduar capacidades con evidencia; y responder
preguntas sobre Savia sin reconstruir el repo desde cero.

El resultado se denomina **Savia Architecture Model (SAM)**. SAM será un
modelo lógico. F0 determinará su formato y ubicación definitivos.

## 4. Principio rector

```text
MORE CAPABILITY WITH LESS MARGINAL COMPLEXITY
MORE AUTONOMOUS EXECUTION WITH UNCHANGED HUMAN AUTHORITY
MORE GOVERNANCE WITH LESS MECHANICAL OVERHEAD
MORE ARCHITECTURAL KNOWLEDGE WITH LESS DOCUMENTATION DRIFT
```

## 5. Invariantes constitucionales

```text
CAN_EXECUTE != HAS_AUTHORITY_TO_DECIDE
EXECUTION_AUTHORITY != DECISION_AUTHORITY
FRONTEND_ADAPTER != POLICY_OWNER
TOOL != EFFECT
CAPABILITY != AUTHORITY
POPULARITY != TRUST
USAGE != CORRECTNESS
OBSERVATION != AUTHORITY
DOCUMENTATION != RUNTIME_TRUTH
IMPLEMENTED != VERIFIED
VERIFIED_SYNTHETIC != VERIFIED_OPERATIONAL
SUPPORTED != IMPLEMENTED
COMPONENT_PASS != SYSTEM_PASS
CI_PASS != OPERATIONAL_GRADUATION
PERFORMANCE_OPTIMIZATION MUST NOT INCREASE AUTHORITY
LESS_MECHANICAL_WORK != LESS_GOVERNANCE
UNUSED != SAFE_TO_DELETE
FAILURE MUST NEVER SILENTLY INCREASE AUTHORITY
UNKNOWN + SECURITY/AUTHORITY → FAIL_SAFE
```

## 6. No objetivos

SE-397 no debe crear otro policy engine, planning registry, receipt system o
knowledge graph si sirve uno existente; sustituir `.scm`; duplicar Vaults,
SE-396 o SE-037; implementar SE-395; aumentar autonomía; elevar L3/L4;
introducir policy por frontend; convertir telemetría en autoridad, métricas en
trust o autoedición en decisiones humanas; retirar capacidades automáticamente;
optimizar sacrificando enforcement; ni producir un score opaco que sustituya
evidencia.

## 7. Reconciliación obligatoria antes de persistir

### 7.1 ID

Verificar que SE-397 continúa libre en specs, planning, projects, docs,
registries y referencias canónicas. Si está ocupado, no sobrescribir y usar el
siguiente ID disponible según lifecycle canónico.

### 7.2 Inventario

Reconciliar SE-037, SE-378, SE-388, SE-390, SE-391, SE-393, SE-394, SE-395,
SE-396 y cualquier spec posterior relevante. Clasificar cada requisito:
`EXISTING_AND_SUFFICIENT`, `EXISTING_BUT_INCOMPLETE`, `NEW_GAP`, `CONFLICT` u
`OBSOLETE`.

### 7.3 Regla

`NO DUPLICATION BY DEFAULT`. Si existe autoridad suficiente: `REUSE / EXTEND`.

## 8. Savia Architecture Model — SAM

SAM representará varias vistas sobre un único modelo lógico, no cinco fuentes
de verdad independientes.

```text
                     HUMAN
                       │ authority / criterion
                       ▼
                     SAVIA
                       │
       ┌───────────────┼────────────────┐
       ▼               ▼                ▼
   GOVERNANCE       EXECUTION         CONTEXT
       └───────────────┼────────────────┘
                       ▼
                    STATE
                       ▼
              EVIDENCE / EVALS
                       ▼
               ADAPTER BOUNDARY
          ┌────────────┼────────────┐
          ▼            ▼            ▼
       FRONTEND      PROVIDER       DOMAIN
                       ▼
                     MODEL
```

El dibujo es una vista generada, no la arquitectura.

## 9. Vistas arquitectónicas

SAM producirá como mínimo:

1. **Foundation View**: identidad, principios, authority, sovereignty,
   policy-as-code, evidence, human gates, risk y lifecycle; distingue
   `PRINCIPLE`, `POLICY`, `IMPLEMENTATION`, `EVIDENCE`.
2. **Capability View**: reutiliza `.scm` y añade `implemented_by`, `uses`,
   `exposed_by`, `governed_by`, `executed_through`, `evidenced_by`.
3. **Structural View**: `SYSTEM`, `SUBSYSTEM`, `COMPONENT`, `MODULE`, `STORE`,
   `POLICY`, `HOOK`, `AGENT`, `SKILL`, `COMMAND`, `ADAPTER`, `FRONTEND`,
   `PROVIDER`, `MODEL`, `MCP`, `DOMAIN_PACK`, `CAPABILITY`, `EVIDENCE_TYPE`,
   `STATE_STORE`, `EXTERNAL_SYSTEM`.
4. **Runtime Flow View**: `INTENT → CONTEXT → CAPABILITY → RISK/AUTHORITY →
   POLICY → GATES → EXECUTION → RESULT → EVIDENCE → STATE/MEMORY`, con
   variaciones por frontend, effect, risk, domain, provider/model y fallo.
5. **Authority & Trust View**: quién puede decidir qué mediante
   `HAS_CAPABILITY`, `HAS_EXECUTION_AUTHORITY`, `REQUIRES_HUMAN_GATE`,
   `ENFORCES`, `DENIES`, `ALLOWS`, `REQUESTS_APPROVAL`, `USES_TRUST`,
   `USES_CONFIDENTIALITY`, `CANNOT_OVERRIDE`. Ningún edge aprendido eleva
   authority.
6. **Evidence View**: `CLAIM → IMPLEMENTATION → TEST → RECEIPT → EVIDENCE →
   GRADUATION`, con `UNIT`, `SYNTHETIC`, `INTEGRATION`, `OPERATIONAL`,
   `LONGITUDINAL`. Ausencia nunca es PASS.
7. **Failure & Degradation View**: `NORMAL`, `DEGRADED`, `DEGRADED_SAFE`,
   `BLOCKED`, `NEEDS_HUMAN`, `UNKNOWN_EFFECT`, `RECOVERY` y relaciones de
   fallo, fallback, degradación, recuperación, reconciliación y bloqueo.

## 10. Grafo arquitectónico

Relaciones mínimas candidatas: `CONTAINS`, `IMPLEMENTS`, `USES`, `CALLS`,
`TRIGGERS`, `DEPENDS_ON`, `READS`, `WRITES`, `ROUTES_TO`, `ENFORCES`,
`VALIDATES`, `OBSERVES`, `PRODUCES`, `CONSUMES`, `GATES`, `EVIDENCES`,
`EXPOSES`, `RESOLVES`, `INVALIDATES`, `FALLS_BACK_TO`, `DEGRADES_TO`,
`REQUIRES`, `REQUIRES_AUTHORITY`, `REQUIRES_HUMAN`, `OVERRIDES`,
`SUPERSEDES`, `DUPLICATES`, `OVERLAPS_WITH`. F0 validará cuáles aportan valor.

## 11. Provenance del modelo

Cada nodo y edge significativo indicará procedencia: tipo (`discovered`,
`declared`, `inferred`, `verified`), path, revision y commit. Estados:
`DECLARED`, `DISCOVERED`, `INFERRED`, `VERIFIED_STATIC`,
`VERIFIED_INTEGRATION`, `VERIFIED_OPERATIONAL`. Nunca `INFERRED = VERIFIED`.

## 12. Arquitectura declarada vs descubierta

Separar intención declarada de estructura descubierta:

```text
DECLARED - DISCOVERED → MISSING_IMPLEMENTATION
DISCOVERED - DECLARED → UNDOCUMENTED_ARCHITECTURE
RELATION_CHANGED      → ARCHITECTURE_DRIFT
```

No corregir automáticamente.

## 13. Architecture Drift Detection

Detectará componente desaparecido o nuevo, dependencia nueva, policy owner
cambiado, hook nuevo en hot path, adapter nuevo, isla de policy por frontend,
capability sin implementación, implementación sin capability, claim sin
evidence, nueva effect surface, dependencia externa o cambio de authority path.
Output inicial `ARCHITECTURE_DRIFT_REPORT`, solo `REPORT_ONLY`.

## 14. Architectural Impact Analysis

Para un file, component, policy, capability, hook, adapter o spec, devolverá
dependencias directas/transitivas, capabilities, flows, authority paths,
evidence, tests, frontends, domains y risk. No ejecutará cambios.

## 15. Arquitectura consultable

F0 decidirá si la interfaz es CLI, command, skill, MCP o API interna. Queries:
`architecture explain`, `dependencies`, `impact`, `flow`, `authority`,
`evidence`, `failures`, `drift`, `health`. La interfaz es adapter; SAM es core.

## 16. Arquitectura humano-readable

Podrá generar vistas bajo `docs/architecture/current/` solo si encajan con la
estructura existente. Serán artefactos no editables manualmente, marcados
`GENERATED FROM SAM` con commit, timestamp y revision.

## 17. Diagramas

Permitirá Mermaid/Graphviz por system, subsystem, flow, effect, frontend,
domain o failure path. `DIAGRAM != SOURCE OF TRUTH`; evitar mega-diagramas.

## 18. Operational Self-Knowledge

SAM conectará existencia con ejecución, verificación, degradación, coste y
obsolescencia, sin copiar telemetría cruda. Separar `ARCHITECTURE` de
`OBSERVATIONS`.

## 19. Savia Operational Trace

Definir trace causal con, si no existe autoridad equivalente: `operation_id`,
`session_id` opaco, frontend, capability, effect, risk, architecture/policy
path, hooks evaluados/ejecutados/bloqueantes/asíncronos, procesos, MCP calls,
context bytes/tokens, tiempos de gates/ejecución/evidence/total, result,
block_reason y degradation_state. No registrar secretos, contenido sensible
innecesario ni prompt completo por defecto.

## 20. Arquitectura ↔ runtime

`TRACE → FLOW INSTANCE → ARCHITECTURE PATH`, para localizar latencia, policy
bloqueante, procesos, fallos y fallbacks.

## 21. Hot Path Architecture

Reconciliar SE-037. Extender `HOOK LATENCY` a `SYSTEM OPERATION COST` sobre
`USER_INTENT → FRONTEND → CONTEXT → ROUTING → GOVERNANCE → EXECUTION →
EVIDENCE → RESULT`, midiendo cada segmento.

## 22. Clasificación del hot path

Clasificar mecanismos `ENFORCEMENT`, `OBSERVABILITY`, `MAINTENANCE`,
`ADVISORY`. Solo enforcement debe bloquear el hot path, salvo policy explícita
que convierta evidence en condición de validez. No reclasificar seguridad para
ganar rendimiento.

## 23. Gate routing

Investigar `EVENT → FAST RELEVANCE CLASSIFICATION → RELEVANT POLICY SET →
MINIMAL BLOCKING ENFORCEMENT → EFFECT → NON-AUTHORITY WORK`. Objetivo: misma
gobernanza con menos trabajo mecánico, sin policy duplicada.

## 24. Session Policy Context

Investigar cache revision-aware de project, branch, domain, frontend, risk
ceiling, policy revision, active spec y confidentiality context. No cachear
decisiones mutables sin revision.

## 25. Subprocess Budget

Medir spawn count/time, fallos, duplicaciones y wrappers. Sustituir in-process
solo con equivalencia semántica probada; no traducir policy a implementaciones
divergentes.

## 26. Execution Envelope

Para OpenCode/bwrap medir `ARG_MAX`, argv/env bytes, binds totales/únicos/
duplicados, logical command y sandbox envelope. Separar comando lógico de
ejecución sandbox. El envelope no contaminará context, transcript, memory ni
receipts. No reducir aislamiento.

## 27. Context Architecture

Representar `SYSTEM_CONTEXT`, `POLICY_CONTEXT`, `USER_CONTEXT`, `TASK_CONTEXT`,
`DOMAIN_CONTEXT`, `KNOWLEDGE_CONTEXT`, `TOOL_CONTEXT`, `TELEMETRY_CONTEXT`.
Medir bytes, tokens, duplicación y fuentes hacia `MINIMAL RELEVANT CONTEXT`.

## 28. Context usefulness

Investigar `Useful Context Density = useful_context / total_context` con método
reproducible y sin autoevaluación exclusiva del mismo modelo. Puede ser NO_GO.

## 29. MCP Architecture

Clasificar MCPs como `REQUIRED`, `OPTIONAL`, `LAZY`, `SESSION_SCOPED`,
`TOOL_SCOPED`, `POLICY_CRITICAL`; medir startup, failure, usage y timeout.
Investigar lazy activation sin perder enforcement.

## 30. Capability Complexity Governance

SAM + `.scm` evaluarán para cada capability: `VALUE_GAIN`, `DEPENDENCY_DELTA`,
`HOT_PATH_DELTA`, `CONTEXT_DELTA`, `SECURITY_SURFACE`, `AUTHORITY_SURFACE`,
`MAINTENANCE_COST`, `EVIDENCE_REQUIREMENT`, `OVERLAP`: su `ComplexityDelta`.

## 31. Capability Lifecycle

Separado del lifecycle de specs: `EXPERIMENTAL`, `ACTIVE`, `STABLE`, `DORMANT`,
`DEPRECATED`, `RETIRED`. `STABLE != MORE_AUTHORITY`.

## 32. Capability overlap

Detectar `IDENTICAL`, `SUBSUMED`, `PARTIAL_OVERLAP`, `COMPLEMENTARY`,
`CONFLICTING` entre agents, skills, commands, hooks, policies, validators,
adapters y capabilities. Inicialmente report-only, nunca consolidación automática.

## 33. Dormancy

Usage es señal, no autoridad: `CANDIDATE → EVIDENCE → HUMAN_REVIEW → DORMANT →
DEPRECATED → RETIRED`. Preservar provenance y evitar eliminación automática.

## 34. Resilience Model

Fault Matrix mínima: crash de frontend, provider timeout/429/5xx, pérdida de
red, MCP o Shield no disponible, hook timeout/respuesta inválida, leak de
procesos, filesystem read-only, disco lleno, receipt failure, ejecución parcial,
efecto externo ambiguo, config corrupta, policy/cache stale, Vault/model no
disponible, context overflow, cancelación y restart. Por fallo: expected state,
authority effect, degradation, recovery, evidence y resultado visible.

## 35. Failure invariants

Ante fallo authority nunca aumenta. Un componente ausente no convierte BLOCK
en ALLOW. Efecto externo ambiguo es `UNKNOWN_EFFECT`, no safe-to-retry.
Observability no bloquea salvo contrato. Dependencia de security/authority
ausente: fail-safe.

## 36. Controlled Fault Injection

Fixtures L0-L2 reproducibles: daemon no disponible, timeout, malformed
response, proceso muerto, config corrupta, temp FS read-only, adapter
interrumpido, 429, 500, stale revision. Nunca producción, secretos, efectos
destructivos, coste externo o sabotaje compartido.

## 37. Recovery

Probar `HEALTHY → FAULT → DEGRADED_SAFE → RECOVERY → HEALTHY`, sin process/FD
leak, stale lease/lock/authority, efecto duplicado, phantom receipt ni pérdida
silenciosa.

## 38. Operational Graduation Model

Matriz: `IMPLEMENTED`, `UNIT_VERIFIED`, `SYNTHETIC_VERIFIED`,
`INTEGRATION_VERIFIED`, `OPERATIONAL_VERIFIED`, `RESILIENCE_VERIFIED`,
`PERFORMANCE_VERIFIED`, `LONGITUDINAL_VERIFIED`. `SUPPORTED` requiere contrato
explícito y dimensiones aplicables según riesgo.

## 39. Multi-frontend Semantic Equivalence

Corpus común: `READ`, `SEARCH`, `EDIT`, `WRITE`, `TEST`, `BUILD`, `SAFE_BASH`,
`BLOCKED_BASH`, `SECRET_ACCESS`, `MCP_CALL`, `EXTERNAL_EFFECT`,
`SCOPE_EXPANSION`, `HUMAN_DECISION`, `CANCEL`, `RETRY`, `RECOVERY`. Comparar
decision, effect, risk, authority, receipt, provenance, failure mode y latency.
Exigir equivalencia semántica, no implementación idéntica.

## 40. Agnosticismo verificable

Separar `FRONTEND`, `PROVIDER`, `MODEL`, `DOMAIN`; una sustitución parcial no
demuestra las demás. Estados: `VERIFIED`, `NOT_VERIFIED`, `NOT_AVAILABLE`,
`NOT_AUTHORIZED`, `FAILED`. Nunca `NOT_AVAILABLE → PASS`.

## 41. Golden Operational Corpus

Incluir inspect/search repo, small edit, test, diagnose/fix/rerun, comandos
seguros/bloqueados, secret attempt, MCP/provider unavailable, retry de efecto
ambiguo, human gate, context-heavy operation, agent workflow, restart y
recovery. Congelar corpus revision, decisiones esperadas e invariantes, no el
lenguaje generado.

## 42. Longitudinal Stability

Sesiones controladas de 30m, 2h y 4h según coste; medir latency drift, memory,
FD/process count, temporales, caches, context, timeouts, errores, receipts y
trabajo duplicado. Preferir local/fixtures.

## 43. Architecture Health

Vector, no score opaco: `ARCHITECTURE_COHERENCE`, `CORRECTNESS`, `SECURITY`,
`AUTHORITY`, `RESILIENCE`, `PERFORMANCE`, `PORTABILITY`, `EVIDENCE`,
`COMPLEXITY`, cada uno con status, evidence, freshness y limitations.
Security/Authority aplican floor y no se compensan con performance.

## 44. Claim ↔ Evidence Consistency

Relacionar claims públicos con la evidencia exigida por graduation policy. Un
claim sin evidencia produce `CLAIM_EVIDENCE_MISMATCH`. No corregir README
automáticamente ante ambigüedad.

## 45. Documentation Truth

Objetivo: `SYSTEM REALITY = ARCHITECTURE MODEL = GENERATED DOCUMENTATION`, con
diferencias explícitas. README es proyección humana, no source of truth.

## 46. Counts semantics

Formalizar scopes `TOTAL`, `CORE`, `DOMAIN`, `GENERATED`, `LEGACY`,
`FRONTEND_SPECIFIC` para evitar contradicciones aparentes entre conteos válidos.

## 47. Architecture Decision Integration

Relacionar `COMPONENT → DECIDED_BY → DECISION_RECORD` sin copiar ADR, para
responder por qué existe la arquitectura además de cómo es.

## 48. Spec Integration

Relacionar componentes, flows y capabilities con specs mediante
`GOVERNED_BY_SPEC`, `EVOLVED_BY`, `PROPOSED_BY`. `related` no prueba
implementación.

## 49. Change Impact Gate

Inicialmente report-only. Producirá `ArchitectureImpact` con componentes,
flows, capabilities, authority paths, frontends, domains, evidence, tests,
risk delta y complexity delta. Enforcement requiere evidencia y aprobación
humana.

## 50. Architecture Drift Gate

Fase inicial report-only; futuro enforcement selectivo para casos como authority
edge no documentado, policy ownership por frontend, retirada de seguridad o
claim sin evidencia. No activar enforcement al merge de esta spec.

## 51. Operational SLOs

No fijar valores sin baseline. Clases: `LOW_RISK_READ`, `LOW_RISK_WRITE`,
`GOVERNED_WRITE`, `SECURITY_CRITICAL`, `EXTERNAL_EFFECT`, `HUMAN_GATE`.
Security-critical puede sacrificar performance.

## 52. Hipótesis de mejora

Tras baseline: governance median -60%, p95 -40%, subprocess low-risk -50%,
context duplication -30%. Son hipótesis recalibrables, con condiciones
absolutas `ZERO NEW FALSE ALLOWS`, `ZERO AUTHORITY ESCALATION`,
`ZERO SECURITY REGRESSION`.

## 53. Arquitectura objetivo operacional

```text
INTENT → MINIMAL RELEVANT CONTEXT → CAPABILITY RESOLUTION
       → MINIMAL RELEVANT GOVERNANCE → AUTHORIZED EXECUTION
       → EVIDENCE → STATE → ASYNC NON-AUTHORITY WORK

               HUMAN AUTHORITY
                      ↓
            CANONICAL SAVIA POLICY
                      ↓
             SAVIA ARCHITECTURE
        ┌─────────────┼─────────────┐
        ▼             ▼             ▼
     Claude        OpenCode       Codex
      Code            │
        └─────────────┼─────────────┘
                      ▼
             SEMANTIC EQUIVALENCE
```

No frontend policy islands.

## 54. Fases

### F0 — Architectural Reconciliation

Reducir incertidumbre: verificar ID; inventariar specs, activos arquitectónicos
y `.scm`; identificar fuentes de autoridad, graph/model y herramientas de
dependencias; reconciliar SE-037/SE-396; producir coverage matrix. No implementar
SAM completo. Output: requirement, existing authority/artifact, status,
evidence, gap y recommendation.

### F1 — Architecture Baseline

Primer SAM mínimo solo con elementos verificables: system, subsystem,
component, capability, policy, adapter, frontend, store y evidence; relaciones
contains, implements, uses, depends-on, enforces, produces y requires-authority.

### F2 — Runtime & Authority Model

Añadir runtime flows, effects, risk, authority, human gates y fallos. Golden
flows: READ, EDIT, WRITE, BASH, MCP y EXTERNAL_EFFECT.

### F3 — Architecture Verification

Comparar declared/discovered y producir drift, claim/evidence e impact reports,
todos report-only.

### F4 — Operational Trace

Conectar ejecución real con architecture path, medir baseline y reconciliar
SE-037.

### F5 — Hot Path Excellence

Optimizar solo tras medición: effect parity, fail-fast, bwrap/E2BIG, hook
fan-out, subprocess, MCP startup y context amplification.

### F6 — Resilience

Fault Matrix, fault injection y recovery.

### F7 — Complexity Governance

Overlap, dormancy, ComplexityDelta y lifecycle, report-only.

### F8 — Semantic Substitution

Frontend × provider × model × domain con evidencia operacional.

### F9 — Longitudinal Validation

Sesiones prolongadas, leaks, drift, performance y recovery.

### F10 — Graduation

Revisión humana para decidir enforcement, consolidaciones, claims y gaps.

## 55. Dependencia con SE-396

SE-396 mantiene prioridad sobre integridad crítica. SE-397 no reemplaza
H01-H12.

```text
SE-396 → TRUSTWORTHY EXECUTION FOUNDATION
SE-397 → SYSTEM-LEVEL ARCHITECTURAL KNOWLEDGE + OPERATIONAL EXCELLENCE

SE-396 critical gaps → SE-397 F0-F4 → F5-F6 → F7-F9
                     → SE-395 adaptive experiments
```

SE-395 offline puede continuar si no rompe WIP ni prerequisitos.

## 56. Acceptance Criteria

- AC01: ID verificado o reasignado sin colisión.
- AC02: SE-037/SE-396 y relacionadas reconciliadas.
- AC03: no se crea policy/planning/receipt/evidence paralelo.
- AC04: `.scm` reutilizado como capability layer.
- AC05: SAM mínimo versionado y machine-readable.
- AC06: Foundation View disponible.
- AC07: Capability View conectada a `.scm`.
- AC08: Structural View disponible.
- AC09: Runtime Flow View disponible.
- AC10: Authority View disponible.
- AC11: Evidence View disponible.
- AC12: Failure/Degradation View disponible.
- AC13: provenance en cada dato relevante.
- AC14: declared vs discovered diferenciados.
- AC15: architecture drift report reproducible.
- AC16: architecture impact analysis reproducible.
- AC17: queries arquitectónicas mínimas disponibles.
- AC18: diagramas generados desde SAM.
- AC19: Golden Operational Corpus definido.
- AC20: Operational Trace conectado con architecture path.
- AC21: SE-037 reconciliada y baseline hot-path disponible.
- AC22: Security corpus PASS.
- AC23: Authority corpus PASS.
- AC24: sin E2BIG en golden corpus tras remediation.
- AC25: Fault Matrix completa para critical paths.
- AC26: recovery `HEALTHY→DEGRADED_SAFE→HEALTHY` demostrada.
- AC27: sin leaks materiales longitudinales.
- AC28: semantic frontend equivalence evaluada.
- AC29: sustituciones evaluadas o `NOT_VERIFIED` explícito.
- AC30: capability overlap report reproducible.
- AC31: ComplexityDelta disponible.
- AC32: capability lifecycle disponible.
- AC33: claim/evidence mismatch detectable.
- AC34: freshness ligada a architecture dependencies.
- AC35: README/support claims reconciliables con evidence.
- AC36: zero new false allows.
- AC37: zero authority escalation.
- AC38: zero security regression.
- AC39: rollback demostrado.
- AC40: graduation requiere decisión humana.

## 57. Definition of Done

SE-397 no está DONE porque exista SAM, sino cuando Savia demuestra end-to-end
quién es, cómo está compuesta, qué puede hacer, qué la gobierna, qué ruta usa,
qué authority aplica, qué evidence existe, cómo falla y recupera, qué cuesta,
de qué depende, qué impacto tiene cambiarla y qué sigue desconocido. Debe poder
responder `UNKNOWN` cuando falte evidencia.

## 58. Consultas de aceptación conceptual

Debe poder responder con SAM + repo reality + operational evidence: cómo
funciona, arquitectura actual, por qué existe un componente, policy de
WRITE_WORKSPACE, quién aprueba merge, ruta Edit por frontend, generadores de
receipts, dependencias de `shell-bridge.ts`, degradación de Shield, dependencia
de Vaults/MCPs, gaps de evidencia, coupling por frontend, hot path y latencia,
overlaps, drift, impacto de PR y agnosticismo demostrado.

## 59. Evidence package

Cada fase producirá commit SHA, timestamp, environment, SAM revision,
architecture hash, policy revision, frontend version, provider/model cuando
aplique, corpus hash, tests, metrics, receipts, drift, limitations, known
unknowns y decision. Sin secretos.

## 60. Rollback

Toda optimización será reversible; routers OFF por defecto hasta graduation;
dormancy inicialmente reversible. Corrupción o indisponibilidad de SAM degrada
la consulta, nunca aumenta permisos. Canonical policy sigue siendo autoridad:
SAM describe y conecta, no sustituye enforcement.

## 61. Human Gates

Requieren decisión humana: alterar authority, trust o confidentiality; retirar
capability; hacer drift bloqueante; activar router por defecto; reducir security
gates; cambiar policy ownership; declarar frontend soportado o sustitución
operacional; elevar autonomía o L3/L4; aceptar regresión de seguridad.

## 62. NO-GO

Toda investigación puede acabar `GO`, `NO_GO` o `NEEDS_MORE_EVIDENCE`. NO_GO
es válido si SAM duplica knowledge graph, el grafo finge precisión, discovery
no es fiable, routing cuesta más, cache crea stale authority, overlap produce
falsos positivos, lazy MCP daña reliability, usefulness no es medible o
ComplexityDelta no es accionable.

## 63. Instrucción de ejecución inmediata

Tras recibir esta spec: **no implementar F1-F10**. Ejecutar únicamente F0 —
Architectural Reconciliation, para conocer lo existente antes de escribir nueva
arquitectura.

Entregar:

```text
SE-397 F0
status:

HEAD:
ID:
spec_path:

RECONCILIATION
SE-037:
SE-378:
SE-388:
SE-390:
SE-391:
SE-393:
SE-394:
SE-395:
SE-396:

EXISTING ARCHITECTURE ASSETS
capability maps:
architecture docs:
data-flow docs:
context architecture:
authority model:
dependency models:
runtime traces:
evidence model:
failure model:
generated diagrams:
query mechanisms:

SOURCES OF TRUTH
identity:
policy:
authority:
capabilities:
planning:
evidence:
memory:
runtime:

GAPS
existing_and_sufficient:
existing_but_incomplete:
new_gaps:
conflicts:
obsolete:

SAM
existing reusable graph:
recommended logical model:
recommended storage:
recommended generated views:
do_not_duplicate:

F1
minimum viable slice:
files expected:
tests:
evidence:
estimated complexity:

HUMAN DECISIONS REQUIRED:
```

No implementación funcional posterior hasta revisión humana del F0.

### Admisión en ciclo autónomo nocturno

- Aprobación humana de la spec: **sí**, 2026-09-08.
- Trabajo admisible: **solo F0**, read-only salvo sus artefactos de informe.
- F1–F10: excluidas hasta revisión humana del F0.
- Riesgo efectivo de F0: L1; riesgo arquitectónico global: L2.
- Estado del runner: `NOT_STARTED_PREREQUISITES_MISSING`.
- Prerrequisitos pendientes en runtime: doble opt-in y
  `AUTONOMOUS_REVIEWER`; su ausencia no se convierte en aprobación implícita.
- Salida permitida: PR Draft con spec + reconciliación F0; nunca auto-merge.

## 64. Criterio de arquitectura

SAM debe ser `DESCRIPTIVE + VERIFIABLE + QUERYABLE + VERSIONED +
PROVENANCE-AWARE`, pero nunca `AUTHORITATIVE OVER POLICY`.

```text
SAVIA SHOULD KNOW HOW SAVIA WORKS.
BUT KNOWING HOW IT WORKS DOES NOT GIVE IT MORE AUTHORITY.
```

## 65. Evolución conceptual

Savia pasó de ejecutar capacidades, a gobernarlas, incorporar memoria/evidence/
evals/soberanía, y desacoplar frontend/model/provider. La quinta etapa es
comprender y verificar su arquitectura y gobernar el coste de evolucionarla.

## 66. Principio final

```text
THE NEXT EVOLUTION OF SAVIA IS NOT MORE FEATURES.
IT IS ARCHITECTURAL SELF-KNOWLEDGE.
```

Savia debe observar qué es, qué tiene, cómo y por qué funciona, quién tiene
authority, de qué depende, cómo falla y recupera, qué cuesta, qué evidencia
soporta sus claims y qué desconoce.

Se delega la ejecución. Nunca el criterio.
