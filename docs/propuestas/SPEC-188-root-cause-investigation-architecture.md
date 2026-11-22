---
spec_id: SPEC-188
title: Root-Cause Investigation Architecture — meta-spec del sistema causal
status: IMPLEMENTED
status_note: "F1 failure-pattern-memory.sh DONE. F2 Sealed Contracts DONE. F3: decision-trace-writer.py + decision-trace-capture.sh hook + test-causal-confidence-channel.bats + decision-trace-protocol.md presentes; causal-confidence-scorer.py RETIRADO en la poda #1609 (sin consumidor). F4: diagnostic-metrics-tracker.py + fix-survival-check.sh + test-spec188-f4-survival.bats presentes; monthly-diagnostic-report.sh RETIRADO en #1609. Trazas de decisión apagadas por defecto (SAVIA_DECISION_TRACE). Nota original del 2026-06-24 («All components present») corregida el 2026-11-22 al comprobar main."
tier: 1
priority: P0
effort: 6-8h (spec doc) · ~80-120h implementacion completa via sub-specs
era: 200
wave: 1
deps: [SE-072, SPEC-106]
unblocks: [SPEC-043, SPEC-065, SPEC-108, SPEC-125]
origin: active-user-2026-06-04 (analisis sintoma vs causa raiz)
timeline:
  - from: "2026-06-05"
    learned: "2026-06-05"
    value: "PROPOSED"
    source: "docs(spec): SPEC-188 Root-Cause Investigation Architecture meta-spec (#811)"
resource: internal://docs/propuestas/SPEC-188-root-cause-investigation-architecture.md
---

# SPEC-188 — Root-Cause Investigation Architecture

> Estado: PROPOSED · Tier 1 · P0 · Estimacion 6-8h (spec) · Era 200 · Wave 1
> Meta-spec: coordina 4 sub-specs existentes + define 5 piezas nuevas.

## Resumen

El workspace tiene piezas parciales para detectar shortcuts y validar razonamiento, pero **no existe un sistema integrado de investigacion de causa raiz**. Esta meta-spec mapea los componentes actuales (4 sub-specs en distintos estados), identifica 5 gaps no cubiertos, y define la arquitectura que los integra en un sistema causal coherente.

NO duplica las sub-specs. Las coordina, fija contratos entre ellas y anade lo que falta.

## Problema

### El sintoma reportado

Savia tiende a parchear sintomas en vez de investigar causas. Patrones documentados:

- Bajar umbral en vez de investigar por que un test falla con score real (`SPEC-043` problem statement).
- Re-intentar el mismo push 6 veces con variantes del mismo parche en vez de pararse a analizar el patron (`SPEC-065` problem statement).
- Olvidar lecciones aprendidas: el mismo agente repite el mismo error en la siguiente sesion (`SPEC-108` problem statement).
- Dar recomendaciones contra reglas establecidas porque el LLM olvida o no consulta auto-memory (`SPEC-125` problem statement, cita textual de Monica 2026-04-28).

### Por que las piezas actuales no bastan

Hay 4 propuestas en distintos estados, pero ninguna sola resuelve el problema y nadie las coordina:

| Sub-spec | Estado | Alcance | Limitacion |
|---|---|---|---|
| SPEC-043 responsibility-judge | PROPOSED | Hook PreToolUse intercepta shortcuts en Edit/Write | Solo detecta sintomas conocidos (regex Layer 1) + 1 juez Haiku Layer 2; no rastrea recurrencia |
| SPEC-065 execution-supervisor | PROPOSED | session-action-log + reflection prompt en attempt 3+ | Advisory, no bloquea; no persiste cross-session; sin metricas |
| SPEC-108 sentry-rca | PROPOSED | post-tool-failure-log con N=3 patron → memoria del agente | Solo PostToolUseFailure (no Edit/Write exitoso pero shortcut); patron-hash naive |
| SPEC-125 recommendation-tribunal | IN_PROGRESS | 4 jueces inline para recomendaciones conversacionales | Solo advice conversacional; no code changes; no longitudinal |
| SPEC-106 truth-tribunal | IMPLEMENTED | 7 jueces para Reports (output/*.md) | Solo reports; no codigo; async/batch |

**Diagnostico**: hay 4 vectores de defensa propuestos pero el conjunto no forma sistema. No hay contrato comun, no comparten memoria de fallos, no hay metricas longitudinales, no hay artefacto de decision auditable, no hay invariantes selladas que un agente NO pueda alterar.

### Por que es P0

- Sin sistema causal, cada incidente se resuelve ad-hoc.
- El daño es asimetrico: una recomendacion erronea aceptada por la usuaria modifica codigo/arquitectura real.
- Las 4 sub-specs estan estancadas (3 PROPOSED, 1 IN_PROGRESS) porque falta el marco que las integra. Esta meta-spec lo aporta.

## Sistema actual — mapeo completo (estado 2026-06-04)

### Capa 1 — Gates pre-action (deterministicos)

| Componente | Donde | Que hace | Que NO hace |
|---|---|---|---|
| `commit-guardian` | pre-commit | bloquea force-push, no-verify, secrets, banned unicode | no analiza intencion del cambio |
| `confidentiality-sign.sh` | pre-commit + CI | firma diff_hash | no audita semantica |
| `block-force-push.ts` | pre-push | regex bloquea --force/--force-with-lease | binario |
| Hooks `validators/*` | PostToolUse Write | frontmatter, spec-status, memory-entry-length, banned-unicode | no analiza shortcuts |

### Capa 2 — Audits post-action (LLM jueces)

| Componente | Estado | Trigger | Output |
|---|---|---|---|
| Truth Tribunal (SPEC-106) | IMPLEMENTED | manual `/report-verify` | score 7 jueces + iteracion |
| Code Review Court | IMPLEMENTED | PR review | 5 jueces + fix rounds |
| Recommendation Tribunal (SPEC-125) | IN_PROGRESS | recomendacion inline detectada | banner verdict |

### Capa 3 — Memoria y aprendizaje

| Componente | Estado | Captura | Consulta |
|---|---|---|---|
| `memory-store.sh` | IMPLEMENTED | decisiones, discoveries (verified-source obligatorio SE-072) | manual, por slug |
| `.claude/external-memory/auto/MEMORY.md` | IMPLEMENTED | indice puntual del usuario | indexado por entrada |
| `feedback_*.md` (`root_cause_always`, `no_overrides_no_bypasses`, etc) | REFERENCED | rules permanentes | memory-conflict-judge consulta |
| Agent self-improvement (SPEC-108) | PROPOSED | patrones N=3 → MEMORY.md del agente | nunca consulta antes de actuar |

### Capa 4 — Reflexion y supervision

| Componente | Estado | Cuando dispara | Bloquea? |
|---|---|---|---|
| `execution-supervisor.sh` (SPEC-065) | PROPOSED | attempt 3+ del mismo action+target | advisory, exit 0 |
| `responsibility-judge` (SPEC-043) | PROPOSED | PreToolUse Edit/Write | si Layer 1+2 confirman SHORTCUT |
| `reflection-validator` (agente) | IMPLEMENTED | invocacion manual | no |
| `coherence-validator` (agente) | IMPLEMENTED | post-output | no |

## Gaps identificados (5)

### G1 — No sealed contract tests

Tests del workspace estan todos en `tests/` con permisos edit/write. No hay separacion entre:
- **Contract tests** (invariantes que un agente NO puede modificar — son el contrato del sistema).
- **Implementation tests** (modificables siguiendo SDD).

**Consecuencia**: un agente que falla en un contract test puede modificarlo en vez de arreglar el codigo. SPEC-043 detecta `pytest.mark.skip` y similares, pero no impide editar la assertion misma a `assert True` o cambiar el threshold del test.

**Ejemplo real proyectable**: agente edita `tests/test-confidentiality-sign.bats` para bajar exit code esperado en vez de arreglar el script real.

### G2 — No calibration channel POST-CODE-CHANGE

Truth Tribunal calibra reports. Recommendation Tribunal calibra advice. **Nada calibra: "acabo de hacer este cambio en codigo, mi confianza en la causa raiz es X"**.

`calibration-judge` existe (Truth Tribunal) pero opera sobre prosa de reports, no sobre commit messages o PR descriptions.

**Consecuencia**: no hay senal estructurada de "DONE con baja confianza causal" vs "DONE con alta confianza causal". El humano revisor no sabe si el agente cree haber arreglado la causa o solo haber silenciado el sintoma.

### G3 — No failure pattern memory con frequency tracking

SPEC-108 propone esto pero sigue PROPOSED. Hoy:
- `feedback_*.md` captura reglas permanentes (cualitativo).
- `memory-store.sh` captura decisiones puntuales.
- **NO existe**: `feedback_root_cause_always.md` referenciado por `memory-conflict-judge` — el path no esta garantizado.

Hallazgo (este turno): `memory-conflict-judge.md` cita `feedback_root_cause_always.md` pero el fichero no existe en el runtime memory path ni en el repo. **La memoria que esta regla asume es invisible al sistema**. Path canonico decidido en Fase 0: `.claude/rules/domain/feedback/feedback_root_cause_always.md` (N1, tracked, passes Shield).

**Consecuencia**: el sistema referencia memoria que no existe. Los patrones de fallos recurrentes (ej. "agente X ha intentado bajar threshold 5 veces este mes") no se rastrean, no se cuentan, no se consultan al inicio de un turn.

### G4 — No diagnostic quality metrics longitudinales

No se mide si un fix sobrevive o re-falla:
- mutation-audit (opt-in, beta) detecta zombies puntualmente.
- test-runner mide pass/fail del commit.
- **NO existe**: "fix del commit X sobrevivio Y dias / Z runs sin re-fallar".

**Consecuencia**: imposible distinguir empiricamente entre "fix de causa raiz" y "parche de sintoma" a posteriori. Un parche de sintoma falla en T+N dias; un fix real no. Sin senal, ambos se ven iguales en el commit log.

### G5 — No decision trace artifact

Cuando un agente toma una decision (elegir threshold, elegir patron de codigo, elegir arquitectura), no genera artefacto estructurado:
- Observacion (que datos vio).
- Interpretacion (que infirio de esos datos).
- Alternativas consideradas (que mas penso).
- Eleccion (que escogio y por que).

`code-comprehension-report` (skill) cubre algo parecido POST-IMPLEMENTACION, pero no es obligatorio ni estructurado para decisiones individuales.

**Consecuencia**: el humano revisor (E1 SDD) no puede auditar el RAZONAMIENTO, solo el RESULTADO. Si el resultado parece bien pero la cadena causal es erronea, el revisor no tiene como verlo.

## Solucion

**Sistema causal integrado de 5 piezas nuevas + 4 sub-specs coordinadas**.

Las 4 sub-specs existentes (SPEC-043, 065, 108, 125) son **vectores de defensa puntuales**. Esta meta-spec los integra anadiendo lo que falta para formar sistema. La arquitectura:

```
+----------------------------------------------------------+
|                  ROOT-CAUSE INVESTIGATION                |
|                                                          |
|   ANTES de actuar    DURANTE accion    DESPUES de actuar |
|   ---------------    ---------------   ----------------- |
|   [P1] Failure        [SPEC-043]       [P2] Causal       |
|       pattern         responsibility   confidence        |
|       memory          judge            channel           |
|       (NUEVO)         (sub-spec)       (NUEVO)           |
|                                                          |
|   [SPEC-125]          [P5] Decision    [P4] Diagnostic   |
|   recommendation      trace            quality metrics   |
|   tribunal            artifact         (NUEVO)           |
|   (sub-spec)          (NUEVO)                            |
|                                                          |
|   [P3] Sealed         [SPEC-065]       [SPEC-108]        |
|       contract        execution        sentry-rca        |
|       tests           supervisor       (sub-spec)        |
|       (NUEVO)         (sub-spec)                         |
+----------------------------------------------------------+
```

## Disenio — las 5 piezas nuevas (P1-P5)

### P1 — Failure Pattern Memory (resuelve G3)

**Que es**: store SQLite + JSON en `.claude/external-memory/failure-patterns/` con esquema:

```sql
CREATE TABLE failure_patterns (
  pattern_id TEXT PRIMARY KEY,       -- hash(agent + error_class + file_glob)
  agent TEXT NOT NULL,
  error_signature TEXT NOT NULL,     -- 2 primeras lineas error, normalizadas
  file_glob TEXT,                    -- ej tests/**/*.bats
  occurrences INTEGER DEFAULT 1,
  first_seen TEXT NOT NULL,          -- ISO-8601
  last_seen TEXT NOT NULL,
  human_lesson TEXT,                 -- opcional, escrito por humano post-mortem
  status TEXT DEFAULT 'open'         -- open | acknowledged | resolved
);
```

**Quien escribe**: post-tool-failure-log (extiende SPEC-108).
**Quien consulta**:
- `responsibility-judge` (SPEC-043) al evaluar shortcut → contexto sobre cuantas veces este agente ha caido aqui.
- `recommendation-tribunal` (SPEC-125) inline → si recomendacion coincide con patron abierto, banner WARN.
- Comando manual `/failure-patterns list|show|resolve`.

**Diferencia con `memory-store.sh`**:
- memory-store guarda decisiones puntuales (1 entrada = 1 evento).
- failure-patterns guarda agregaciones con frequency (1 entrada = N eventos del mismo patron).

**Bridge con `feedback_*.md`**: cuando `occurrences ≥ 10`, sugerir promocion a regla permanente `feedback_*.md`.

**Feature flag**: `SAVIA_FAILURE_PATTERN_MEMORY_ENABLED=1` (default `0` hasta validacion Fase 1). Off-switch sin codigo: `=0` desactiva escritura y lectura; el resto del sistema funciona sin P1.

**Bridge SE-072**: cada insert requiere `verified_source` no nulo (`tool:post-tool-failure-log` por default). Cumple axioma verified-memory.

### P2 — Causal Confidence Channel (resuelve G2)

**Que es**: campo estructurado en commit message + PR body + spec status updates:

```
Causal-Confidence: high | medium | low
Causal-Evidence: <ref a archivo:linea | test que confirma | benchmark | repro steps>
Symptom-Surface: <que sintoma desaparece con este cambio>
Root-Cause-Claim: <una frase con la causa que el agente cree haber resuelto>
```

**Cuando es obligatorio**:
- Commits de agentes (no humanos directos).
- PR body cuando hay cambios en `src/`, `scripts/`, `.claude/hooks/`, `tests/`.
- Spec status transitions (PROPOSED → IN_PROGRESS → IMPLEMENTED).

**Validacion** (hook PreCommit):
- Campo presente: requerido si agent commit.
- `Causal-Confidence: low` requiere `Causal-Evidence` no vacio o bloquea.
- `Causal-Confidence: high` con cero referencias verificables → escalado a juez `calibration-judge` adapted (modo code).

**Output**: PR template anadira esta seccion. Court orchestrator la lee.

**Feature flag**: `SAVIA_CAUSAL_CONFIDENCE_ENABLED` (default off hasta validacion Fase 3).

**Bridge SE-072**: `Causal-Evidence` debe respetar el axioma de fuente verificada (ver SE-072).

### P3 — Sealed Contract Tests (resuelve G1)

**Que es**: directorio `tests/contracts/` con tests marcados como invariantes:
- Hook PreToolUse Edit/Write rechaza modificaciones en `tests/contracts/**` salvo:
  - Cambio firmado por humano con commit message `[contract-change]` + revisor humano OBLIGATORIO.
  - Add (nunca modify/delete).

**Que tests son contract**:
- Lineas rojas de `savia-ethical-principles.md` (L1-L5).
- Invariantes de seguridad (`block-force-push.ts`, `confidentiality-sign.sh` core).
- Spec acceptance criteria que el equipo declara congelados.

**Diferencia con tests normales**: tests normales en `tests/*.bats` pueden refactorizarse por agentes (siguiendo SDD). Contract tests son **fortaleza**: si un agente falla contra ellos, debe arreglar codigo, no test.

**Migracion**: subset inicial pequeno (5-10 tests) en `tests/contracts/`. Crecimiento por opt-in humano.

### P4 — Diagnostic Quality Metrics (resuelve G4)

**Que es**: tracking longitudinal de fixes en `.claude/external-memory/fix-survival/`:

```jsonl
{"ts":"2026-06-04T22:00:00Z","commit":"abc123","spec":"SPEC-184","file":"hooks/post-write-validate.sh","claim_root_cause":"set -uo pipefail position","confidence":"high","tags":["hook","validator"]}
```

**Que se mide automaticamente** (cron diario via skill `fix-survival-check`):
- Para cada fix tracked, contar si el archivo o test relacionado ha vuelto a fallar.
- Calcular metrica: `survival_days = days_since_commit AND no_related_failure`.
- Agregar por agente: `agent_survival_p50, p90`.

**Output mensual**: report en `output/fix-survival-{YYYYMM}.md` con ranking de agentes y patrones recurrentes.

**Senal accionable**: si un agente tiene `survival_p50 < 7 dias`, escalado a humano para revisar prompt o tooling.

### P5 — Decision Trace Artifact (resuelve G5)

**Que es**: artefacto JSON generado por agentes en decisiones no-triviales:

```json
{
  "decision_id": "uuid",
  "ts": "ISO-8601",
  "agent": "dotnet-developer",
  "task_ref": "SPEC-XXX-slice-N",
  "observation": "Test FailureXYZ throws NullReferenceException at line 42",
  "interpretation": "Auth middleware returns null for unauthenticated requests, but downstream service assumes non-null",
  "alternatives_considered": [
    {"option": "Add null check downstream", "rejected_because": "treats symptom, not cause"},
    {"option": "Add explicit Unauthenticated() guard in middleware", "rejected_because": "changes contract; breaks 3 callers"},
    {"option": "Return AuthResult.Unauthenticated() with null user marker", "selected": true, "reason": "preserves contract, propagates intent, downstream handles explicitly"}
  ],
  "evidence_refs": ["src/Auth/Middleware.cs:78", "test/AuthTests.cs:142"],
  "causal_confidence": "high"
}
```

**Donde se guarda**: `.claude/external-memory/decision-traces/{YYYYMM}/{decision_id}.json`.

**Cuando es obligatorio**:
- Cambios en `src/` con LOC ≥ 30.
- Cambios en `.claude/hooks/` (cualquier LOC).
- Status transitions de specs (PROPOSED → IMPLEMENTED).
- Cuando `responsibility-judge` Layer 2 evalua SHORTCUT (forzado para revertir).

**Quien lee**:
- Code Review Court: contexto extra para correctness/architecture judges.
- Humano E1 review: rationale auditable.
- `failure-pattern-memory` (P1) cuando se detecta re-fall.

## Contratos entre piezas

```
+--------------+   read    +---------------------+
|   SPEC-043   |---------->|  P1 Failure Pattern |
| responsibility|<----------|       Memory        |
|     judge    | append    +---------------------+
+--------------+                     ^
       |                             | append
       v                             |
+--------------+   write   +---------------------+
|  SPEC-065    |---------->|  Decision Trace P5  |
|  execution   |<----------|     Artifact        |
|  supervisor  | read      +---------------------+
+--------------+                     ^
       |                             | feed
       v                             |
+--------------+           +---------------------+
|  SPEC-108    |---------->|   P2 Causal         |
|  sentry-rca  | feed      |   Confidence Field  |
+--------------+           +---------------------+
                                     ^
                                     | validate
                                     |
                           +---------------------+
                           |   SPEC-125          |
                           |   recommendation    |
                           |   tribunal          |
                           +---------------------+

+-----------------------------+
|  P3 Sealed Contract Tests   |   <- enforced by PreToolUse hook
+-----------------------------+
+-----------------------------+
|  P4 Diagnostic Quality Mtx  |   <- cron + report
+-----------------------------+
```

## Scope

### In scope

- Definir las 5 piezas nuevas (P1-P5) con esquema, ubicacion, contratos.
- Definir contratos entre sub-specs (043, 065, 108, 125) y piezas nuevas.
- Crear `feedback_root_cause_always.md` real (cierra hallazgo G3).
- Plan de implementacion incremental (no big-bang).
- Tests BATS que validen estructura mensual de los stores (no completitud — eso es de sub-specs).

### Out of scope

- Implementacion completa de las sub-specs (SPEC-043, 065, 108, 125 mantienen su scope individual).
- Refactor de Truth Tribunal (SPEC-106) — sigue cubriendo solo reports.
- Cambios a Code Review Court — sus 5 jueces no cambian.
- Reescritura de `memory-store.sh` — P1 es store adicional, no reemplazo.
- Replacement de mutation-audit — sigue opt-in.

## Acceptance criteria

1. Documento `docs/propuestas/SPEC-188-root-cause-investigation-architecture.md` (este) presente y referenciado en ROADMAP.
2. `feedback_root_cause_always.md` creado en path canonico `.claude/rules/domain/feedback/` (resuelve hallazgo G3).
3. Para cada pieza nueva P1-P5, este documento define:
   - Esquema de datos.
   - Path de ubicacion.
   - Quien escribe y quien lee.
   - Trigger de obligatoriedad.
   - Diferencia con piezas existentes.
4. Contratos cruzados entre P1-P5 y SPEC-{043,065,108,125} explicitos.
5. Plan de implementacion fasificado (4 fases) con sub-spec por fase.
6. Tests BATS `tests/test-spec-188-architecture.bats` validan:
   - Documento presente y con frontmatter correcto.
   - Las 5 piezas estan documentadas (sections P1-P5 presentes).
   - feedback_root_cause_always.md existe en path canonico.
7. CHANGELOG.md: entrada `### Añadido — SPEC-188 — Root-Cause Investigation Architecture`.
8. ROADMAP.md: SPEC-188 en Active Stack como PROPOSED.
9. Confidentiality signature firmada tras edicion.

## Tests

### Test 1 — Estructura del documento (BATS)

`tests/test-spec-188-architecture.bats`:

```bash
@test "SPEC-188 documento existe y tiene frontmatter" {
  [ -f docs/propuestas/SPEC-188-root-cause-investigation-architecture.md ]
  grep -q '^spec_id: SPEC-188' docs/propuestas/SPEC-188-root-cause-investigation-architecture.md
  grep -q '^status:' docs/propuestas/SPEC-188-root-cause-investigation-architecture.md
}

@test "SPEC-188 documenta las 5 piezas P1-P5" {
  for p in "P1 — Failure Pattern Memory" "P2 — Causal Confidence Channel" "P3 — Sealed Contract Tests" "P4 — Diagnostic Quality Metrics" "P5 — Decision Trace Artifact"; do
    grep -qF "$p" docs/propuestas/SPEC-188-root-cause-investigation-architecture.md
  done
}

@test "SPEC-188 referencia las 4 sub-specs coordinadas" {
  for s in SPEC-043 SPEC-065 SPEC-108 SPEC-125; do
    grep -qF "$s" docs/propuestas/SPEC-188-root-cause-investigation-architecture.md
  done
}

@test "SPEC-188 identifica 5 gaps G1-G5" {
  for g in "G1 — No sealed contract tests" "G2 — No calibration channel POST-CODE-CHANGE" "G3 — No failure pattern memory" "G4 — No diagnostic quality metrics" "G5 — No decision trace artifact"; do
    grep -qF "$g" docs/propuestas/SPEC-188-root-cause-investigation-architecture.md
  done
}

@test "feedback_root_cause_always.md existe en path canonico" {
  [ -f .claude/rules/domain/feedback/feedback_root_cause_always.md ]
}

@test "SPEC-188 status es PROPOSED inicial" {
  grep -q '^status: PROPOSED' docs/propuestas/SPEC-188-root-cause-investigation-architecture.md
}
```

### Test 2 — Coherencia roadmap

Validar que SPEC-188 aparece en `docs/ROADMAP.md` como PROPOSED en Active Stack.

## Riesgos

| Riesgo | Probabilidad | Mitigacion |
|---|---|---|
| Sub-specs estancadas siguen estancadas tras meta-spec | media | Fase 1 desbloquea SPEC-108 (es la mas barata) y demuestra valor inmediato |
| Sobre-ingeneria: 5 piezas nuevas + 4 sub-specs es mucho | alta | Implementacion fasificada (P1+P3 primero — alto valor, bajo coste); evaluacion entre fases |
| Failure Pattern Memory crece sin freno | media | Politica TTL: patrones resueltos > 90 dias se archivan; status `acknowledged` no se reincrementa |
| Sealed Contract Tests genera friccion excesiva | media | Subset inicial pequeno (5-10 tests); opt-in growth; bypass humano documentado |
| Causal Confidence se rellena perfunctorio ("high" siempre) | alta | calibration-judge adapted en modo code; samplig 10% de PRs reviewed por humano |
| Decision Trace Artifact infla repo | media | Guardar en `.claude/external-memory/` (gitignored o subrepo separado) |
| Conflicto con SPEC-106 (Truth Tribunal) por solapamiento | baja | Truth Tribunal sigue cubriendo SOLO reports; jueces de TT pueden compartirse pero no su orchestrator |
| Hallazgo G3 (feedback_root_cause_always.md inexistente) bloquea memory-conflict-judge ya en uso | alta | Fase 0 (1h): crear el fichero con contenido inicial; cierra deuda tecnica detectada |

## Plan de implementacion (fasificado)

### Fase 0 — Cerrar deuda tecnica detectada (1h)
- Crear `.claude/rules/domain/feedback/feedback_root_cause_always.md` con contenido canonico. Path elegido por estar en N1 (`.claude/rules/`), tracked en repo, y pasar Savia Shield sin friccion. Alternativas descartadas: `.claude/external-memory/feedback/` (gitignored, no canonico), `.claude/feedback/` (no N1, bloqueado por Shield Ollama AMBIGUOUS).
- Validar `memory-conflict-judge` ya no referencia path inexistente.
- Commit aparte: `fix(memory): create missing feedback_root_cause_always.md (SPEC-188 Fase 0)`.

### Fase 1 — P1 Failure Pattern Memory + desbloqueo SPEC-108 (~16h)
- Implementar store SQLite + scripts CLI (`failure-patterns list|show|add|resolve`).
- Extender `post-tool-failure-log.sh` para escribir patrones agregados.
- Marcar SPEC-108 IN_PROGRESS y completar su Parte 1 sobre P1.
- Tests: `tests/test-failure-pattern-memory.bats`.

### Fase 2 — P3 Sealed Contract Tests (~8h)
- Crear `tests/contracts/` con 5-10 tests iniciales.
- Hook PreToolUse rechaza Edit/Write a `tests/contracts/**` sin `[contract-change]` + humano.
- Documentacion: `docs/rules/domain/sealed-contract-tests.md`.
- Tests: `tests/test-sealed-contracts.bats`.

### Fase 3 — P2 Causal Confidence Channel + P5 Decision Trace (~24h)
- Definir trailer schema y PR template update.
- Hook PreCommit valida presencia y coherencia.
- `calibration-judge` adapted en modo code-change (Sonnet).
- Decision trace JSON schema + write hook desde agentes (initial: dotnet, typescript, python developers).
- Tests: `tests/test-causal-confidence.bats`, `tests/test-decision-trace.bats`.

### Fase 4 — P4 Diagnostic Quality Metrics + integracion sub-specs (~32h)
- Cron skill `fix-survival-check` (semanal).
- Report mensual generator.
- Coordinar SPEC-043 + SPEC-065 + SPEC-125 con piezas nuevas (contratos formales).
- Validacion completa del sistema integrado: tests end-to-end.

## Trazabilidad

- Origen: peticion del usuario activo (2026-06-04) — analisis "sistema actual sintoma vs causa raiz".
- Documento base: `docs/rules/domain/savia-ethical-principles.md` §3 (Responsabilidad), §6 (Sostenibilidad cognitiva), §13 (criterio ultimo).
- Sub-specs coordinadas: SPEC-043, SPEC-065, SPEC-108, SPEC-125.
- Spec relacionada (no coordinada): SPEC-106 (Truth Tribunal — reports).
- Bridge: SE-072 (verified-memory-axiom) — todo el storage de P1-P5 debe cumplir axioma.

## Open questions

1. **¿La meta-spec se aprueba completa o por fases?**
   Recomendacion: aprobar meta-spec completa (este documento) → cada Fase requiere su propia sub-spec ejecutable a partir de Fase 1.

2. **¿Decision Trace se guarda en repo (visible) o en .claude/external-memory/ (privado)?**
   Recomendacion: external-memory por defecto (volumen). Anonymized summaries promovidas a repo bajo demanda.

3. **¿Sealed Contract Tests son git-protected o solo hook-protected?**
   Recomendacion: hook-protected primero (rapido, reversible). Evaluar git pre-receive hook en server post-Fase 2.

4. **¿Failure Pattern Memory comparte schema con `memory-store.sh` (SQLite vs Markdown)?**
   Recomendacion: SQLite dedicado (queries de frequency requieren tabla, no markdown). Bridge unidireccional: patrones consolidados pueden generar entrada en `memory-store` como `discovery`.

5. **¿Causal Confidence Channel afecta a commits humanos directos?**
   Recomendacion: NO. Solo commits de agentes (detectados por `Author: ` matching agent pattern o commit trailer `Agent-Author: true`).

## Archivos afectados

- `docs/propuestas/SPEC-188-root-cause-investigation-architecture.md` (nuevo, este)
- `tests/test-spec-188-architecture.bats` (nuevo)
- `.claude/rules/domain/feedback/feedback_root_cause_always.md` (nuevo — Fase 0, path canonico)
- `CHANGELOG.md` (edit, 1 entrada)
- `docs/ROADMAP.md` (edit, 1 entrada Active Stack)
- `.confidentiality-signature` (auto re-firma)

## No afecta

- Sub-specs SPEC-043, SPEC-065, SPEC-108, SPEC-125 en su scope individual (esta meta-spec las coordina, no las reemplaza).
- Truth Tribunal (SPEC-106) — sigue cubriendo reports.
- Code Review Court — sus 5 jueces no cambian.
- 13 principios eticos + 5 lineas rojas — sin tocar.
- Codigo de proyectos (`projects/**`) — esta meta-spec opera en infrastructura del workspace, no en producto cliente.
