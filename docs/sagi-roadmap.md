# SAGI Roadmap — Savia AGI por orquestación (L11) · modulo de desarrollo

> **HISTÓRICO (2026-09-26).** Este roadmap ya no rige. Ruta vigente: `docs/ROADMAP.md` (ADR-002); estado: `docs/propuestas/planning-state.json`.


> **Fuente de verdad**: `labs/` (privado, sin remote) — hipótesis L11, protocolo v1.2
> y plan de ejecución aprobado 2026-08-21. Este documento es su **vista pública
> sanitizada**: roadmap de desarrollo accionable, sin métricas de runs, sin paths
> de `labs/`, sin detalle N2+ (CRIT-001, política de LPs 2026-08-21).
> Estado: vision general — los detalles de cada prueba viven en la cúpula SaviaLabs.

---

## Tesis

SAGI (Savia AGI) plantea que el flujo AGI es **un algoritmo determinista
versionado que usa el LLM como procesador heurístico reemplazable sobre el
sustrato Savia** — no un modelo más grande. Si el LLM cambia, el algoritmo
sigue (ART-01, CRIT-002); si el algoritmo desaparece, el LLM es un chat sin
memoria. El programa SCL ya implementó el sustrato (captura, ciclo de vida,
métrica L, federación): SAGI es el orquestador que lo cierra en un flujo
AGI medible, alineado con los niveles de autonomía (mapeo L0-L3 Savia ↔
DeepMind, política activa) y con el límite innegociable "la IA propone, la
operadora dispone" (CRIT-031).

## Cómo se integra con el roadmap de desarrollo

| Pieza | Estado | Dónde |
|---|---|---|
| Sustrato de aprendizaje (captura→ciclo→métrica L→federación) | F0-F5 implementado | `docs/SCL-ROADMAP.md` |
| Prioridad de descubrimiento (regla eager) | Se-335 merged | `docs/rules/domain/knowledge-discovery-priority.md` |
| Turn-SDLC: auditor de fases + DoD de respuesta + telemetría `order_ok` | SE-336 merged | `docs/specs/SE-336-turn-sdlc.spec.md` |
| **Telemetría de errores → incidentes → aprendizaje** | SE-534 S1+S2 IMPLEMENTADO | `docs/specs/SE-534-telemetry-intelligence.spec.md` |
| Orquestador SAGI (fix-loop reusable) | SCL-011/012/013 IMPLEMENTADO, en producción | `docs/specs/SCL-011-orquestador-sagi.spec.md` |

## Roadmap de desarrollo (por orden)

### H1 — Blindar la telemetría como sensor del bucle (SE-534 S1+S2) ✅
- Fingerprint determinista de errores: agrupar "este error apareció N veces".
- Alerta con umbral que alimenta el hook de captura SCL (el bucle aprende del
  incidente).
- **Estado**: IMPLEMENTADO — SE-534 S1+S2 mergeado (PR #982). 8 BATS verdes + CI.

### H2 — Robustez del agnosticismo (run-3, P1 con un segundo modelo)
- Replicar la prueba de aprendizaje continuo con un modelo distinto (mid/heavy
  o local vía modo de emergencia).
- **Criterio**: si converge igual, el flujo lo produce el algoritmo, no el modelo.
- **Presupuesto**: ~8-10K tokens. **CRIT-001**: local si está disponible; nunca
  datos N3+ a cloud.

### H3 — Criterio estable con señal real (run-3, P3)
- 10 dilemas de criterio; el algoritmo consulta `CRITERIO.md` y mide coherencia
  (misma decisión + mismo CRIT citado).
- **Por qué primero dentro de P2-P4**: más barato, mayor valor de alineación.
- **Requiere**: orquestador SAGI mínimo versionado (paso H5).

### H4 — Memoria cross-sesión y adaptación a tarea nueva (run-3, P2 y P4)
- P2: sesión nueva sin el hecho — el recall recupera la lección y la aplica.
- P4: tarea no vista — convergencia vía skill + cúpula.
- Nota: P2/P4 comparten infraestructura con H3; P2 relevante hoy gracias a
  SE-335 (descubrimiento cúpulas-primero).

### H5 — Decisión de diseño: orquestador en producción vs investigación
- Decidir si el orquestador SAGI se versiona como artefacto de producción
  (fuera de `labs/`) o permanece como línea de investigación.
- **Si pasa**: candidato a guard/fix-loop reutilizable (patrón auditor
  determinista → LP → recall → re-generación).
- **Es el desbloqueo del resto del programa**: sin el orquestador versionado,
  P6 no se puede formalizar como spec de desarrollo.
- **DECIDIDO 2026-08-22**: el orquestador pasa a producción como **SCL-011**
  (`docs/specs/SCL-011-orquestador-sagi.spec.md`, `scripts/savia-orchestrator.sh`).
  Las pruebas P1-P5 son **SCL-012**. Numeración descolisionada (era
  `labs/specs/SE-335/336`, colisionada con producción) — LP-20260822-5f47cb3d.

### H6 — Flujo end-to-end (P6, test tipo nivel "agente" adaptado)
- "Partir del estado del workspace y lograr un objetivo multi-paso en N pasos
  sin intervención" (p. ej. generar una spec válida desde un PBI).
- **Métrica**: pasos (menos = mejor) + calidad final (auditor) + L.
- **Alineación**: eje "agente" de la autonomía, sin violar CRIT-031 (objetivo
  delegado explícitamente; el algoritmo propone, la operadora dispone).
- **IMPLEMENTADO 2026-08-22**: **SCL-013** (`scripts/sagi-e2e.sh`) — run-1
  determinista valida el mecanismo; run-2 real en la línea L11 (privado).

### H7 — Cierre de la línea y vía de retorno
- Validación humana del ledger L11 + decisión de vía de retorno a código
  (objetivo Labs: ≥3 hallazgos con retorno a producción).
- Contribuciones L11 hasta la fecha: convergencia por auditor-determinista,
  mapeo de autonomía (política activa). Pendiente un tercer hallazgo.

## Dependencias entre hitos

```text
H1 (telemetría) ✅ IMPLEMENTADO (SE-534 S1+S2, #982)
H2 (agnosticismo) puede correr sobre labs/ sin producción
H3 (criterio estable) y H4 (memoria/adaptación) → requieren el orquestador mínimo
H5 (decisión de diseño) ✅ RESUELTA → SCL-011 (orquestador) + SCL-012 (pruebas)
H6 (end-to-end) se formaliza sobre SCL-011/012
H7 (cierre) depende de ≥2 pruebas con mejora medible
```

## Estado de producción (2026-08-23)

**SAGI arrancado en producción sobre LLM local:**

1. **DECIDIR con LLM real**: `savia-orchestrator.sh --decide llm` usa Ollama
   local (127.0.0.1:11434, CRIT-001 — sin cloud). Contrato mínimo
   input=contexto de sustrato → output=propuesta.
2. **Bucle real**: tarea `sagi-orquestador-diario` en `scripts/savia-automations.sh`
   (daily 08:30). El orquestador consolida aprendizaje cada día e inyecta al bucle SCL.
3. **Validación**: P4 converge con LLM real en tarea no vista (2 iteraciones
   alineadas con CRITERIO.md); P2 (memoria cross-sesión) y P3 (criterio estable)
   CONFIRMAN con LLM real (run-3, deepseek-v4-flash / qwen local).
4. **Reto honesto pendiente**: el orquestador persiste LP `INFERRED` — la
   activación a `human_authored` sigue siendo humana (CRIT-031). La
   automatización diaria propone; la operadora activa.

## Retorno a producción (2026-08-23)

| Hallazgo L11/L13 | Retorno | PR |
|---|---|---|
| Convergencia por auditor-determinista (run-2/run-3) | Orquestador SCL-011 como fix-loop | #985-#987 |
| SAGI en producción con DECIDIR local | `savia-orchestrator.sh --decide llm` + automatización | #992 |
| Capa metacognitiva (monitoreo/control) sobre SAGI | `meta-monitor/meta-control/meta-recalibrate` + `--meta` | #993,#994 |
| Harness determinista M1-M4 | `l13-meta-pruebas.sh` — prueba el mecanismo sin LLM | #995 |

Contribuciones al objetivo Labs (≥3 hallazgos con retorno): **3/3 superado** —
convergencia, orquestación en producción, capa metacognitiva.

## Criterios humanos aplicables

- **CRIT-001**: todo run de SAGI en `labs/` (infraestructura propia, sin remote);
  este roadmap y cualquier artefacto de producción no filtran métricas de runs
  ni datos N3+. Detalle de los runs permanece en SaviaLabs.
- **CRIT-031 / ART-11**: ninguna prueba auto-activa sustrato; todo fin en
  propuesta `INFERRED` pendiente de `human_authored`. P6 delega el objetivo por
  decisión humana explícita.
- **Rule #8 (SDD)**: H6 se implementa como spec aprobada antes de orquestación.

## Estado del programa (2026-08-23)

El orquestador SAGI está en producción (SCL-011/012/013, #985-#987), con
monitoreo metacognitivo sobre él (L13 F1/F2/F3, #993-#995).

**L11 CERRADA 2026-08-23** (CONFIRMA run-2 + run-3, retorno 3/3 superado). La
línea SAGI como experimento concluye: el mecanismo quedó en producción.
**L13 (metacognición) CERRADA 2026-08-23** (CONFIRMA 4/4: calibración,
divergencia modula confianza, autorregulación POSTPONE, recalibración con señal
real del ledger) — la capa metacognitiva queda operativa sobre el orquestador.
La siguiente línea viva es **L14 (circuit-closing deuda estructural)**,
preregistrada en SaviaLabs.

Próximos pasos desde este roadmap:

**L13 cierre** — consumar M1-M4 con señal real (ledger) + recalibración.
**H2 (agnosticismo, run-3 P1 con segundo modelo)** — no requiere orquestador
nuevo, corre íntegro en `labs/` (CRIT-001) y su lección se sanitiza al repo como
LP. Alternativa ya priorizable: **H7** (cierre de la línea) — validación humana
del ledger L11 y vía de retorno, con H3 (criterio estable sobre señal real)
como el hito de mayor valor de alineación pendiente.