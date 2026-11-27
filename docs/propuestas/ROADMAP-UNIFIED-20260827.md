---
id: ROADMAP-UNIFIED-20260827
title: "Plan unificado Labs + General — priorización cruzada"
status: SUPERSEDED
superseded_by: ROADMAP.md
priority: P0
area: Planning / Roadmap
---

# Plan Unificado — Savia Labs × Roadmap General (2026-08-27)

> **HISTÓRICO (2026-09-26).** Este roadmap ya no rige. Ruta vigente: `docs/ROADMAP.md` (ADR-002); estado: `docs/propuestas/planning-state.json`.


> Cruz de las dos fuentes de planificación:
> - **General**: `docs/ROADMAP.md` (Critical Path Q2-Q3 pipeline + backlogs P0-P3).
> - **Labs**: `labs/ROADMAP.md` (líneas L1-L27, repriorizada 2026-08-24).
>
> Objetivo: **un solo orden de ejecución** que respete dependencias, valor y
> urgencia, sin duplicar esfuerzo ni dejar que los dos roadmaps diverjan.
> CRIT-001: todo local, sin datos N3+ a proveedor cloud.

---

## 1. Mapa cruzado — dónde convergen y dónde divergen

| Ítem | Labs | General | Estado real | Unificación |
|---|---|---|---|---|
| **L14 Deuda estructural** | **P1** | "siguiente prioridad" (narrativa cierre 2026-08-23) | PREREGISTRADA | **CONVERGENCIA — arranca primero** |
| **SE-338 Rule Manifest** | retorno prod de L14 (rule-manifest) | PROPOSED 2026-08-23 | pendiente revisión humana | **Batch L14** (1º) |
| **SE-339 Coverage Ratchet** | retorno prod de L14 (coverage) | PROPOSED 2026-08-23 | pendiente revisión humana | **Batch L14** (1º) |
| **SE-264 Memory Consolidation** | — | pipeline #29 (spec hecha 2026-08-27) | spec PROPOSED, sin impl | **Batch L14** (higiene) |
| **SE-344 Frónesis como Código** | **P0** | no listado en pipeline | spec PROPOSED (aprobación operadora) | **Batch 2** — requiere aprobación |
| **SE-346 Surrogate** | — | pipeline #28 | **IMPL hoy (PR #1024)** | ✅ CERRADO (fuera del plan) |
| **L23 Cúpulas N1** | **P2** | — | VALIDADA (catálogo), sin apertura | **Batch 3** — habilitador de SE-344 |
| **SE-220-spec (Speculative Tool)** | — | P0 backlog (06-24) | probe mergeado (#856) | **Batch 4** |
| **SE-258 Brechas identitarias** | — | P0 backlog (06-24) | PROPOSED | **Batch 4** |
| **SPEC-182/183 · SE-106 · SE-265** | — | Tier P2 | mixto | **Batch 4** |
| **L26 Savia Evolution** | **P3** | — | PREREGISTRADA | **Batch 5** |
| **L27 Savia Talent** | **P4** (E3/E5 gate) | — | PREREGISTRADA | **Batch 6** |
| **L24/L25 verticales · L12 · L9** | P5-P8 | — | — | **Batch 7** |
| **SE-347 PMA evaluación** | — | S1 done | S2/S3 pendientes | **Track B** (no compite con dev) |

**Convergencias duras**: L14 es P1 en Labs Y "siguiente" en general → único
ítem con doble mandato. Sus piezas de retorno a producción (SE-338 rule-manifest,
SE-339 coverage, SE-264 memory) son el **primer batch real**.

**Conflicto de P0 resuelto**: SE-344 (Labs P0) vs SE-220-spec/SE-258 (general
P0). Unificación: **SE-344 va delante** — es la prioridad más reciente (08-24 vs
06-24), tiene urgencia de ventana (las decisiones seed son de esta semana) y
desbloquea el gate de L27 (ronda). SE-220-spec (18h, grande) espera; su probe ya
está hecho.

**Dependencia a respetar**: SE-344 consume **L23 (taxonomía de dominios)** →
apertura de cúpulas (Batch 3) debe preceder o correr en paralelo al slice de
dominios de SE-344. El schema+CLI de SE-344 Slice 1 no depende de L23 y puede
empezar ya.

---

## 2. Plan unificado de ejecución (orden único)

### Progreso ejecutado (2026-08-27)

| Batch | Estado | PRs |
|---|---|---|
| Batch 1 — L14 | ✅ SE-338 rule-manifest + SE-339 coverage ratchet · SE-264 ya implementado (#905) | #1025 |
| Batch 2 — SE-344 FxC | ✅ CLI fronema + cúpula Fronesia + 6 seed + 13 bats | #1028 |
| Batch 3 — L23 cúpulas N1 | ✅ dome SaviaDomains + 34 cúpulas + generador | #1026 |
| Batch 4 — backlog | ✅ SPEC-182/SE-106/SE-265/SE-258 cerrados + dep-audit CI · **SE-220-spec IMPLEMENTED (PR #874, 2026-06-26)** | #1032 |
| Batch 5 — L26 | ✅ evidencia + FxC + política soberanía/resiliencia | #1029 |
| Batch 6 — L27 | 🔶 E3/E5 gate PASS + E13 auditor + E14 matriz · **E12 Piloto 1 pendiente (VASS obviado)** | #1033 #1034 |
| Batch 7 — verticales | ⏳ L24/L25/L12/L9 | — |
| **Batch 8 — SE-365 Company as Code** | 🔶 estándar de entidades organizacionales (renumerado de SE-265) — en implementación | — |
| **Batch 9 — SE-366..370 (verificación, temporalidad, contratos)** | ✅ SE-366 ledger bitemporal (#1069) · SE-367 derivation path (#1070) · SE-369 contract pins (#1072) · SE-370 research lane (#1067) · SE-368 pendiente | #1067 #1069 #1070 #1072 |
| **Batch 10 — SE-371 cache hygiene + SE-372 savia setup (nuevo, 2026-09-03)** | ✅ SE-371 cache hygiene (#1074) + activación (#1075) + métricas (#1076) · ✅ SE-372 savia setup interactivo (#1077) | #1074 #1075 #1076 #1077 |
| SE-373 savia setup · módulo workspace (multi-repo) | 🟡 PROPOSED (2026-09-03) — composición multi-repo para agentes | — |
| Track B — SE-347 | 🔶 evaluado **RE-EVALUAR** (S3 bloqueado por modelo local ≥8B) | #1027 |
| SE-348 activaciones | ✅ vector + Shield NER + router SE-346 + hook FxC · ⏳ sandbox (sudo) · ⏳ modelo ≥8B (hardware) | #1031 |

### Batch 1 — L14 Deuda estructural (transversal: reduce el coste de todo)
| Ítem | Tipo | Esfuerzo | Nota CRIT-001 |
|---|---|---|---|
| SE-338 Rule Manifest Generator | impl (spec PROPOSED → aprobar) | S (~3-4h) | local, determinista |
| SE-339 Test Coverage Ratchet | impl (spec PROPOSED → aprobar) | S (~3-4h) | local |
| SE-264 Memory Consolidation | impl (spec lista) | S (~3h) | local, `~/.savia-memory` |
| Cierre: metrics de salud (69→≥85) + coverage 23%→40% | verificación | — | — |

### Batch 2 — SE-344 Frónesis como Código (Labs P0, requiere aprobación)
- Spec PROPOSED; **necesita aprobación de la operadora** para arrancar.
- 6h agente + 3h humana. Desbloquea L27 (corpus de fronemas), L26, cantera.

### Batch 3 — L23 Cúpulas N1 (habilitador)
- 3h. Apertura de cúpulas sobre el catálogo validado. Precede a dominios de SE-344.

### Batch 4 — Backlog general P0/P2
- SE-220-spec **IMPLEMENTED** (PR #874, 2026-06-26) · SE-258 (8h) · SPEC-182→SPEC-183 · SE-106 · SE-265.

### Batch 5 — L26 Savia Evolution (P3 Labs)
- 14-18h. Evidencia → L27 + discurso inversor.

### Batch 6 — L27 Savia Talent (P4 Labs)
- 64h total; **E3 (hechos vs humo) + E5 (score sintético) primero** (gate de la ronda VASS).
- SE-344 alimenta E5 (corpus de fronemas).

### Batch 7 — Verticales y cola (P5-P8 Labs)
- L24 Farming · L25 Humanity · L12 Sonora (paralela) · L9 Biomimético.

### Batch 8 — SE-365 Company as Code (P0 transversal, 2026-09-01)
- Estándar de entidades organizacionales como código (renumerado de SE-265, que colisionaba con court-model-tiers).
- Habilita: federación (SE-263), queryability del grafo organizacional, org-registrar skill.
- Consume: SE-352 (origin), SE-355 (audit), SE-363 (records-not-files), SE-362 (risk-tiering).
- Fases: 0 esquema → 1 Company → 2 Projects → 3 Resources → 4 org-registrar.

### Batch 9 — SE-366..370 (verificación, temporalidad, contratos; análisis open-source 2026-09-02)
> 5 specs PROPOSED, esperan aprobación de la operadora. Todas locales (CRIT-001).
> Conectan con L28 (harness/verificación) y L30 (prospectiva) de Savia Labs.

| Spec | Qué aporta | Fuente | Esfuerzo | Depende de |
|---|---|---|---|---|
| **SE-366 Decision Ledger bitemporal** | hechos con validez temporal doble (mundo/Savia) + evidence rows + corrección no destructiva + consulta as-of | grafo bitemporal open-source (U1+U3) | M (~6-8h) | SE-355, SE-352, SE-364 |
| **SE-367 Derivation Path** | veredictos con cadena causal expandible hasta la fuente original; grounding contra trace | derivación con reglas open-source (U5) | M (~5-6h) | L28 M2, courts |
| **SE-368 Review Lifecycle congelado** | freeze del candidato + un registro de autoridad por lineage + cierre en último evento causal + acknowledge one-shot | review lifecycle open-source (G1) | M (~6h) | SE-343, pr-plan, courts |
| **SE-369 Contract Digest Pins** | contratos byte-congelados bajo digest; compat sin autoridad; rechazo explícito de schema nuevo | digest pins open-source (G6) | S (~4h) | SE-363, settings.json |
| **SE-370 SDD Research lane** | investigación como fase SDD con grant exacto y artefacto research.md auditable bajo el change | research lane open-source (G4) | S (~4h) | SDD, web-research |

**Prioridad dentro del batch** (valor/urgencia/dependencia):
1. **SE-366** (mayor hueco: temporalidad+evidencia como propiedad del dato).
2. **SE-368** (robustece el lifecycle de revisión que ya se usa en cada PR).
3. **SE-367** (refuerza grounding de courts, complementa SE-366).
4. **SE-369 / SE-370** (higiene de contratos y SDD).

**No duplica** (ya cubierto): G3 one-shot grants (SE-343), U2 conflict 3-bucket
(SCL-010), L28 M2 grounding (labs).

### Track B (paralelo, no compite) — SE-347 PMA evaluación
- S2 (auditoría de red runtime) + S3 (patrones RLM + benchmark). Independiente de los batches de dev.

---

## 3. Reglas del plan unificado

1. **L14 manda**: cualquier ítem nuevo que duplique coste (pr-plan frágil, gates
   rotos, regeneración manual) se absorbe en Batch 1 antes de priorizar lo nuevo.
2. **Sin aprobación no se implementa**: SE-344, SE-338, SE-339, SE-258 y
   SE-220-spec son PROPOSED → requieren revisión humana (la operadora). Los
   specs con APPROVED/IMPLEMENTED pasan directos.
3. **Gate de dependencia**: Batch 3 (L23) bloquea los slices de dominio de
   SE-344, no su schema.
4. **CRIT-001**: todos los ítems son locales (GP, reglas, memoria, taxonomía,
   fronemas). Nada envía datos N3+ a cloud.
5. **Anti-drift**: ambos roadmaps referencian este documento como fuente de
   prioridad única; se regenera cuando cualquiera de los dos cambie de P0/P1.

---

## 4. Acción inmediata propuesta

1. Aprobar SE-338/SE-339/SE-264 (Batch 1) y SE-344 (Batch 2) → arrancar Batch 1
   en rama `agent/` + PR.
2. Añadir cross-reference en `docs/ROADMAP.md` y `labs/ROADMAP.md`
   (cabecera: "Prioridad única → ROADMAP-UNIFIED-20260827").
3. Anotar en el pipeline general que SE-346 está IMPLEMENTED (fuera del plan).

## 5. Referencias

- `docs/ROADMAP.md` · `labs/ROADMAP.md` · `docs/specs/SE-344-*.spec.md` ·
  `docs/specs/SE-338-*.spec.md` · `docs/specs/SE-339-*.spec.md` ·
  `docs/specs/SE-264-*.spec.md` · `docs/specs/SE-346-*.spec.md` ·
  `docs/specs/SE-366-*.spec.md` · `docs/specs/SE-367-*.spec.md` ·
  `docs/specs/SE-368-*.spec.md` · `docs/specs/SE-369-*.spec.md` ·
  `docs/specs/SE-370-*.spec.md`
- CRIT-001 · `autonomous-safety.md` (la IA propone, la operadora dispone)
