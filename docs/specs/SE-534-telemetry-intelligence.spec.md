# Spec: SE-534 — Telemetry Intelligence: fingerprinting, incident grouping y auto-remediación (inspirado en superlog)

**Status:** PROPOSED → PARCIALMENTE IMPLEMENTADO (S1+S2, 2026-08-22)
**Renumerada:** antes SE-334 (número duplicado con `SE-334-vaults-scl-criteria-hardening`); renumerada a SE-534 por decisión de la operadora, 2026-11-14.
**Decisión 2026-11-14:** sin consumidor; no se cablea; revisar 2027-02-14 si hay errores repetidos. Motivo: solo 27 fallos de despacho en 98 días.
**Fecha:** 2026-08-17
**Area:** Observability / Telemetría / Autonomía / Savia Labs
**Estimación:** ~40h (4 slices)
**Inspirado por:** [superloglabs/superlog](https://github.com/superloglabs/superlog) (Apache 2.0) — sistema de telemetría agéntica open-source (OTLP/OpenTelemetry, fingerprinting de errores, incident grouping con LLM, agent runner auto-correctivo)

**Developer Type:** agent-multi
**Implementación:** otra savia (spec de referencia para un agente distinto)

---

## 1. Origen — comparativa superlog vs Savia

Se analizó `superloglabs/superlog` (v1.3k★, TypeScript, Apache 2.0, YC P26) — un
"workspace de observabilidad agéntica" que ingiere trazas/logs/métricas
OpenTelemetry, **agrupa señales ruidosas en incidentes** y lanza agentes que
**auto-corrigen** el software. Su repo se divide en: `packages/fingerprint`
(huella de errores), `apps/worker` (grouping, agent-run, alerts, PR sweep),
`apps/api`/`apps/web` (superficie de producto).

Savia ya tiene una base sólida de telemetría local-first (SE-313 IMPLEMENTED:
`otel-emit.sh` W3C traceparent, schema, sampling, redacción N1-N4b; `savia-trace.sh`
trazas distribuidas; `incident-rca.sh` SE-323; `telemetry-report.sh`; audit trail
SE-275; dispatch gate SE-313 S7). **Lo que superlog aporta y Savia NO tiene**:

| Capacidad | superlog | Savia hoy | Gap |
|---|---|---|---|
| **Fingerprint de errores** normalizado | `packages/fingerprint`: normaliza mensajes (URLs→`<url>`, UUIDs→`<uuid>`, IPs→`<ip>`, timestamps→`<ts>`, hex→`<hex>`, emails→`<email>`, IDs→`<id>`, request paths→`<path>`, envuelve Anthropic SDK, psycopg), agrupa por `sha256(tipo::mensaje::frames)` | `content-fingerprint.sh` solo sha256 truncado sin normalización semántica | **ALTO** — no se pueden agrupar errores repetidos por similitud |
| **Agrupación de señales en issues** | worker agrupa errores ruidosos por fingerprint → issues → incidentes | No existe; cada evento de `telemetry-events.jsonl` es aislado | **ALTO** — no hay "este error apareció 47 veces" |
| **Incident grouping con LLM** | `grouping/agent.ts`: agente con tool-use loop clasifica issues candidatos y decide incidente | `incident-rca.sh` es manual/determinista (por incidente dado), sin agrupar | **MEDIO** — el RCA existe pero no el agrupado previo |
| **Alertas con umbral** | `alerts/evaluate.ts`: métricas → condiciones → issues | Detectores `always-on` (SE-279) escriben reportes sin máquina de alertas | **MEDIO** |
| **Agente auto-correctivo con PR** | `agent-run.ts` + `agent-pr-sweep.ts`: investiga, genera fix, abre PR | `incident-rca.sh` produce informe, NO abre PR | **MEDIO** — falta el paso final de remediación |
| **Memoria de agente por incidente** | `agent-memories-service.ts`: el agente recuerda incidentes previos | SaviaVaults/Labs pueden, no cableado | **BAJO** |

**Objetivo de negocio medible**: reducir el tiempo de diagnóstico y remediación
de fallos recurrentes de agentes:
- Errores repetidos detectados como **un solo issue** (hoy: eventos sueltos),
  con conteo y primera/última aparición.
- De un error ruidoso → issue agrupado en < 30s tras el evento (sampling de
  errores 100%, SE-313 S4 ya lo garantiza para errores).
- Opcional: PR auto-generado (Draft) con fix cuando el incidente es un fallo de
  dispatch/config recurrente.

**Trade-off explícito**: la agrupación con LLM (slice S3) usa el proveedor local
(Ollama/OPENAI-compatible, ADR-012, sin vendor names). El fingerprint (S1) es
**determinista puro** (sin LLM) — es la pieza de mayor ROI. La auto-remediación
(S4) es opcional y se entrega como PR Draft, nunca mergeada (Rule #8, SE-146).

**Confidencialidad**: el fingerprint normalizado **redacta** identificadores
antes de persistir (N3): nunca guarda URLs/IPs/emails/IDs crudos en el hash ni
en el issue. Coherente con SE-313 S5.

---

## 2. Diseño

### S1 — Fingerprint determinista de errores (14h) — mayor ROI

Port del algoritmo de `packages/fingerprint` a **PURE_BASH + Python** (no
depende de node — el workspace es bash-first).

`scripts/telemetry-fingerprint.py`: dado un evento de telemetría (JSON), computa
la huella normalizada:

```
canonical = tipo :: message_bucket :: [frames_normalizados]
hash = sha256(canonical)[:16]
```

Normalización (`message_bucket`):
- URLs → `<url>` · emails → `<email>` · UUIDs → `<uuid>` · timestamps → `<ts>`
- IPs → `<ip>` · hex (0x… y ≥20 hex chars) → `<hex>` · números → `<n>`
- strings entre comillas → `<str>` · IDs largos (≥20 chars) → `<id>`
- request paths con `/` inicial → `<path>` (colapso anti-scan)
- desenvuelve errores Anthropic-style (`"message": "..."`) para no hashear el
  wrapper JSON (evita que `request_id` per-request filtre al bucket)
- colapsa whitespace, lowercase

Campos del fingerprint: `{hash, exception_type, top_frame, normalized_frames}`.

**Integración**: `otel-emit.sh` gana flag `--fingerprint` que computa y adjunta
`fingerprint.hash` + `fingerprint.bucket` al evento. El evento queda con ambas
cosas: crudo (para diagnóstico) y huella (para agrupación).

**Salida**: `output/telemetry-fingerprints.jsonl` (evento + fingerprint) y
`output/telemetry-issues.jsonl` (issues agrupados: `{issue_id, hash, count,
first_seen, last_seen, sample_event}`).

### S2 — Issues + alertas con umbral (10h)

- `scripts/telemetry-issues.sh`: lee `telemetry-events.jsonl`, agrupa por
  `fingerprint.hash`, mantiene `output/telemetry-issues.jsonl` con conteo,
  primera/última aparición, severidad (error > warn > info).
- Umbral de alerta configurable en `config/telemetry-policies.yaml`
  (p. ej. `alert_on: count >= 5 in 1h` o `severity: error`).
- `scripts/telemetry-alert.sh`: cuando un issue cruza el umbral, emite un alert
  JSON (reutiliza formato de `incident-rca.sh`) y opcionalmente llama al hook
  de captura SCL (el bucle aprende del incidente — cierra el círculo con SCL).

### S3 — Incident grouping con LLM local (8h) — opcional

- `scripts/telemetry-grouping.sh`: dado un issue nuevo + candidatos (issues
  previos), pregunta al proveedor local si el issue es nuevo o variante de uno
  existente. Veredicto `{action: new|merge, target_issue, reason}`.
- Determinista por defecto: si no hay LLM disponible, `--deterministic` decide
  por igualdad de `message_bucket` (sin LLM). El LLM es un refinamiento.

### S4 — Auto-remediación con PR Draft (8h) — opcional, post-S1-S3

- `scripts/telemetry-remediate.sh`: dado un alert de issue recurrente (count ≥
  umbral, p. ej. `dispatch.failed` repetido con el mismo `requested_model`),
  genera un fix propuesto (reutiliza `subagent-dispatch-gate.sh`, SE-313 S7)
  y crea un **PR Draft** en la rama `agent/telemetry-fix-*` (nunca mergea —
  Rule #8, autonomous-safety).

---

## 3. Acceptance criteria

> **Estado 2026-08-22 — S1+S2 IMPLEMENTED** (PR pendiente):
> `scripts/telemetry-fingerprint.py`, `scripts/telemetry-issues.sh`,
> `scripts/telemetry-alert.sh` (+ flag `--fingerprint` en `otel-emit.sh`),
> policy `config/telemetry-policies.yaml`, 8 tests BATS
> (`tests/test-se534-telemetry-fingerprint.bats`). S3/S4 siguen PENDIENTES.

**S1**
- AC-1.1. Dos eventos con el mismo error pero distintos IDs/URLs/timestamps →
  MISMO fingerprint (test con par sintético).
- AC-1.2. Dos eventos con errores distintos → fingerprints distintos (test).
- AC-1.3. `otel-emit.sh --fingerprint` adjunta `fingerprint.hash` + `bucket`
  (test).
- AC-1.4. El fingerprint redacta: el hash y el bucket NO contienen URLs/IPs/
  emails/UUIDs crudos (asercion).
- AC-1.5. Determinista: misma entrada → misma huella (test).

**S2**
- AC-2.1. `telemetry-issues.sh` agrupa N eventos idénticos en 1 issue con
  `count=N` (test).
- AC-2.2. `telemetry-alert.sh` emite alert al cruzar el umbral configurado
  (test con fixture).
- AC-2.3. El alert es JSON válido compatible con `incident-rca.sh` (test).

**S3**
- AC-3.1. `telemetry-grouping.sh --deterministic` decide new/merge por
  `message_bucket` sin LLM (test).
- AC-3.2. Con LLM local disponible, el veredicto es `{action, target, reason}`
  (test o skip si no hay Ollama).

**S4**
- AC-4.1. `telemetry-remediate.sh` genera PR Draft en rama `agent/telemetry-*`
  para un issue recurrente (test con dry-run; NUNCA mergea).
- AC-4.2. El fix propuesto nunca se aplica automáticamente (asercion — Rule #8).

**Transversal**
- AC-5.1. Todo script `set -uo pipefail`, `bash -n` pasa, guard de agnosticismo
  CLEAN (0 vendor names en el código del bucle).
- AC-5.2. Ningún script escribe fuera del sustrato (markdown/JSONL) salvo el
  PR Draft explícito de S4.

---

## 4. Benchmark comparativo (superlog vs SE-534)

Para validar que el fingerprint de SE-534 agrupa igual que el de superlog, se
usa un corpus de fixtures idéntico (errores con URLs/UUIDs/timestamps/paths):

| Caso | superlog | SE-534 esperado |
|---|---|---|
| Mismo error, distinto UUID | mismo hash | mismo hash (AC-1.1) |
| Mismo error, distinta URL | mismo hash | mismo hash |
| Error con request path `/wp-admin` vs `/.env` | mismo hash (colapso `<path>`) | mismo hash |
| Error distinto (mensaje diferente) | hash distinto | hash distinto (AC-1.2) |
| Envelope Anthropic con `request_id` distinto | mismo hash | mismo hash |
| psycopg error con params distintos | mismo hash | mismo hash (si se portea el normalizador) |

El port no necesita ser 1:1 (los hash values pueden diferir — lo que importa es
la **relación de equivalencia**: qué errores colapsan juntos). Se valida con
tests de equivalencia sobre el corpus, no comparando hashes byte a byte.

---

## 5. Decisiones de diseño (ADR-lite)

- **D-1: Python para el fingerprint, no bash puro.** La normalización de regex
  (URLs/UUIDs/emails/paths) es significativamente más mantenible en Python y ya
  es dependencia disponible (python3 siempre presente). `otel-emit.sh` sigue
  siendo bash; delega el fingerprint a `telemetry-fingerprint.py`.
- **D-2: huella determinista + LLM opt-in.** El valor de ROI está en la
  agrupación determinista (S1). El LLM (S3) es refinamiento opcional — no
  introduce latencia ni coste en el path crítico.
- **D-3: issues agregan, no reemplazan.** `telemetry-events.jsonl` (crudo) se
  conserva para diagnóstico; `telemetry-issues.jsonl` es la vista agregada. No
  se descarta el crudo (auditabilidad, SE-275).
- **D-4: la auto-remediación es PR Draft, nunca merge.** Coherente con Rule #8
  (SDD) y autonomous-safety. El PR es una propuesta para el humano.

---

## 6. Riesgos

| Riesgo | Mitigación |
|---|---|
| R1: fingerprint demasiado agresivo colapsa errores distintos | Bucket de mensaje conservador: quita solo identificadores, preserva contenido alfabético (patrón superlog `messageBucketFor` vs `normalizeMessage`); tests AC-1.2 |
| R2: agrupación con LLM añade fricción/latencia | Determinista por defecto; LLM opt-in y solo como refinamiento (S3) |
| R3: auto-remediación produce PR basura | Solo para issues con fingerprint idéntico y count ≥ umbral alto; PR siempre Draft, nunca merge; opcional (S4) |
| R4: volumen de telemetry crece | Sampling tail ya en SE-313 S4 (errores 100%, routine 5%); issues agregan, no multiplican |
| R5: PII en fingerprints | Redacción previa (AC-1.4); coherente con SE-313 S5 y block-credential-leak |
| R6: el port del fingerprint diverge del de superlog | Benchmark de equivalencia (Sección 4) en CI |

---

## 7. Verification method

1. Suite BATS `tests/test-se-334-telemetry-intelligence.bats` (≥ 15 tests).
2. E2E: inyectar 5 eventos con el mismo error (IDs distintos) → 1 issue count=5
   → alert al cruzar umbral → (opcional) PR Draft con dry-run.
3. Guard de agnosticismo CLEAN sobre los scripts nuevos.
4. Benchmark de equivalencia (Sección 4) sobre el corpus compartido.

---

## 8. Integración con el ecosistema

- **SE-313** (telemetría OTel): el fingerprint se añade como atributo del evento
  `savia.event/1.0`; no reemplaza la emisión.
- **SE-323 / SCL**: el alert de S2 alimenta `incident-rca.sh` y el hook de
  captura SCL (la lección aprende del incidente).
- **SE-275** (audit trail): los issues agrupados se registran en el audit log.
- **autonomous-safety**: S4 genera PR Draft en rama `agent/*`, nunca mergea.
- **SCL-003/005**: los fingerprints se indexan en la cúpula SaviaLearning como
  atributo de las lecciones — el recall semántico puede recuperar "este error
  ya pasó 47 veces, la lección es X".

---

## 9. No incluido (con motivo)

- **Dashboard web** (superlog `apps/web`): SPEC-191 ya la cubre (bloqueada por
  savia-web infra). SE-534 produce los datos que el dashboard consumiría.
- **Postgres/ClickHouse** (superlog `apps/db`): Savia es local-first JSONL
  (ADR-006 texto como verdad); la migración a base de datos es una decisión
  estratégica separada, no de este spec.
- **OTLP ingest proxy** (superlog `apps/proxy`): SE-313 ya decide OTLP opt-in
  (`SAVIA_OTLP_ENDPOINT`). El proxy es infra de despliegue, no del bucle.
- **Memoria de agente por incidente** (superlog `agent-memories-service`):
  SaviaVaults ya provee la base; cablearlo es follow-up (SCL), no este spec.

---

## 10. Estimación

| Slice | Esfuerzo | ROI | Depende de |
|---|---|---|---|
| S1 fingerprint determinista | 14h | **ALTO** (base de todo) | SE-313 S1/S4 |
| S2 issues + alertas | 10h | **ALTO** | S1 |
| S3 grouping LLM | 8h | MEDIO | S1, Ollama |
| S4 auto-remediación PR | 8h | MEDIO (opcional) | S1-S2, SE-313 S7 |
| **Total** | **40h** | | |

---

## 11. Referencias

- superlog: github.com/superloglabs/superlog (Apache 2.0) — `packages/fingerprint`,
  `apps/worker/src/grouping/`, `alerts.ts`, `agent-run.ts`, `agent-pr-sweep.ts`
- SE-313: `docs/propuestas/SE-313-observabilidad-trazabilidad-agentes-eu-ai-act.md`
- SE-323: incident RCA (`docs/propuestas/SE-323-incident-rca.md`)
- SPEC-191: `docs/propuestas/SPEC-191-savia-telemetry.md`
- SCL: `docs/specs/SCL-003-recall-operativo.spec.md`, `docs/specs/SCL-005-embeddings-hibridos.spec.md`
