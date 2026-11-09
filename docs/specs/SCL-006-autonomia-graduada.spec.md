# SCL-006 — Autonomía graduada por p_consistent

**Status:** APPROVED → IMPLEMENTED (2026-08-17)
**Fecha:** 2026-08-17
**Area:** Autonomía / Seguridad / SE-292 S6
**Branch:** agent/scl-001-aprendizaje-continuo
**Estimación:** ~3h

---

## Origen

SE-292 S6 define `p_consistent` (fracción de ejecuciones consistentes) como
medida de fiabilidad. SCL-001 la usa en la métrica `L`. Lo que falta: que
`p_consistent` gobierne el **nivel de autonomía** que una tarea/dominio puede
ejecutar. Una tarea con consistencia baja no debe poder ejecutarse de forma
autónoma; con consistencia alta puede escalar. La autonomía se gradúa por
evidencia medible (CRIT-019), no por decreto.

## Diseño

```
p_consistent < 0.50 → L0 (draft, sin ejecución autónoma)
0.50 ≤ p < 0.70     → L1 (report-only)
0.70 ≤ p < 0.85     → L2 (assisted)
p ≥ 0.85            → L3 (unattended) — solo con historial + aprobación humana
```

`learning-autonomy.sh` determina el nivel permitido y decide si una solicitud
(`--requested`) se concede. L3 degrada a L2 si no hay `--history-ok` +
`--human-ok` (gates de loop-phasing, docs/rules/domain/loop-phasing.md).

## Acceptance criteria

- AC-1. p < 0.5 → solo L0; pedir L1 se deniega (test).
- AC-2. 0.5 ≤ p < 0.7 → L1 concedido (test).
- AC-3. 0.7 ≤ p < 0.85 → L2 concedido, L3 denegado (test).
- AC-4. p ≥ 0.85 sin historial+humano → degrada a L2, L3 denegado (test).
- AC-5. p ≥ 0.85 + historial + humano → L3 concedido (test).
- AC-6. Pedir menos de lo permitido siempre se concede (test).
- AC-7. `--json` emite JSON válido (test).
- AC-8. Valor fuera de rango → error (exit 3) (test).

## Verification method

1. Suite BATS `tests/test-scl-006-autonomia.bats` (8 tests).
2. Alineación con loop-phasing L0-L3 (docs/rules/domain/loop-phasing.md).

## Out of scope

- Implementación del gate L0-L3 en cada skill/agente (eso es loop-phasing ya
  existente): SCL-006 provee la decisión de autonomía; su enforcement se delega
  a los gates de skills/agentes.
- p_consistent dinámico por dominio (medición continua): sigue en SE-292 S6.

## Referencias

- SE-292 S6: p_consistent
- loop-phasing L0-L3: `docs/rules/domain/loop-phasing.md`
- Script: `scripts/learning-autonomy.sh`

## Enmienda propuesta 2026-11-09 (repriorización tras Savia Viva R6)

> Propuesta en la misma PR que SE-513, SE-514 y SE-515. No cambia el estado de esta spec; vale cuando la operadora fusione la PR.

- **Límite conocido**: el nivel que calcula `learning-autonomy.sh` no lo aplica nadie; es informativo. Ninguna cifra concede autonomía (SE-497 R13, SE-515).
