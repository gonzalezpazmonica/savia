# SCL-011 — Orquestador SAGI: integra sustrato, cúpulas, criterio y bucle SCL

**Status:** APPROVED (operadora, 2026-08-22) → IMPLEMENTED 2026-08-22
**Fecha:** 2026-08-22
**Area:** Orquestación / Epistemología / SAGI (L11)
**Línea de investigación:** L11 (SAGI por orquestación)
**Estimación:** ~8h
**Base verificada:** main 2026-08-22 — SCL-001..010 IMPLEMENTED, SE-534/335/336, SaviaVaults v0.2, CRITERIO.md

> **Renumeración (2026-08-22)**: esta spec era `labs/specs/SE-335-sagi-orchestrator.spec.md`
> (PROPOSED, investigación). SE-335 estaba colisionado con la spec de producción
> "prioridad de descubrimiento". Al pasar a producción pasa a **SCL-011**, con las
> pruebas a **SCL-012**. Evidencia: LP-20260822-5f47cb3d.

---

## 1. Origen — el gap del programa

SCL-001..010 implementaron el bucle de aprendizaje **cerrado, medido y
agnóstico**; SaviaVaults v0.2 provee memoria en cúpulas con grafo y federación;
CRITERIO.md es la autoridad única de criterio (SCL-008). Cada componente existe y
funciona aislado. **Lo que no existe es el orquestador que los integra en un bucle
de decisión continuo.**

La hipótesis L11: al componer los 4 pilares (sustrato + cúpulas + criterio +
bucle SCL) con un orquestador mínimo, el sistema muestra **comportamiento de SAGI
emergente** — aprendizaje sin re-entrenar, memoria cross-sesión, criterio estable,
adaptación a tarea nueva, escalado multi-agente — que ningún componente aislado
exhibe.

**Objetivo medible**: >=2 de 5 pruebas (SCL-012) muestran mejora sobre baseline.

**Trade-off**: orquestador PURE_BASH mínimo (~200 líneas) que COMPONE los scripts
existentes; no reimplementa nada. CRITERIO y CONSTITUCION intocables (CRIT-031,
ART-11); el orquestador propone, la operadora dispone.

## 2. Diseño — orquestador mínimo

```
tarea ──► LEER: CRITERIO.md (human_authored) + cúpula (recall) + learning props
        ──► DECIDIR: LLM con contexto sustrato (contrato mínimo input→output)
        ──► PERSISTIR: learning-proposal --persist
        ──► MEDIR: learning-metric.sh (L)
        ──► AJUSTAR: autonomía por p_consistent (SCL-006)
```

**Script**: `scripts/savia-orchestrator.sh`
- Compone: `learning-recall.sh` (SCL-003/005), `learning-proposal.sh --persist`
  (SCL-001/002), `learning-metric.sh` (SCL-003), `learning-autonomy.sh` (SCL-006).
- Agnóstico a LLM (PURE_BASH), sin vendor names (guard SCL-004/SE-534).
- Límite CRIT-031: todo output es propuesta `INFERRED`; solo la operadora activa.

**DECIDIR con LLM real (2026-08-22)**: `--decide llm` usa Ollama local
(127.0.0.1:11434, CRIT-001 — datos nunca a cloud), contrato mínimo input=contexto
de sustrato → output=propuesta. Default sigue siendo `none` (shadow determinista);
`SAGI_LLM_MODEL` configura el modelo local. Validado: P4 converge con LLM real en
tarea no vista (2 iteraciones alineadas con CRITERIO.md). Cableado en
`scripts/savia-automations.sh` (tarea `sagi-orquestador-diario`, daily 08:30).

## 3. Acceptance criteria

- [x] AC-1. `savia-orchestrator.sh` existe, `set -uo pipefail`, bash -n OK, guard
  de agnosticismo CLEAN (0 vendor names).
- [x] AC-2. Dada una tarea, ejecuta LEER→DECIDIR→PERSISTIR→MEDIR y emite reporte
  con la métrica L (test E2E con fixture).
- [x] AC-3. No escribe fuera del sustrato (markdown/JSONL) salvo el reporte.
- [x] AC-4. No modifica CRITERIO.md ni CONSTITUCION (hash invariante tras N ciclos).
- [x] AC-5. `--dry-run` muestra el plan sin ejecutar.

## 4. Riesgos

| Riesgo | Mitigación |
|---|---|
| R1: duplica lógica existente | Compone scripts, no reimplementa |
| R2: "SAGI" se vuelve afirmación vacía | Solo se afirma si SCL-012 muestra mejora medible |
| R3: auto-modificación del criterio | CRITERIO/CONSTITUCION intocables (AC-4, CRIT-031) |
| R4: coste de integración alto | Fallback: probar P2/P3 (memoria y criterio) primero |

## 5. Verification

1. `bats tests/test-scl-011-orchestrator.bats` (AC-1..AC-5).
2. E2E con fixture: tarea de referencia → reporte con L emitido.
3. Guard de agnosticismo CLEAN.

## 6. Referencias

- SCL-012 (pruebas P1-P5), `docs/sagi-roadmap.md` (H5 decide producción).
- L11: cúpula SaviaLabs (protocolo v1.2).
- CRITERIO.md (autoridad), CRIT-031 (no auto-activación).

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Límite conocido**: `read_sustrate` pide el recall en modo `shadow` y solo cuenta hits; `L` se calcula con `p_consistent=0.5`, `divergence=0.2` e `ignorance-resolved=0.1` cuando nadie pasa datos. Esa salida es una ruta reproducible, no una medida de aprendizaje. SE-515 S1 la marca `no medido` y conecta el recall efectivo.
