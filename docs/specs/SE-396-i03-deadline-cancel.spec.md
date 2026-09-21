---
status: IMPLEMENTING
implementation_state: IMPLEMENTED_PENDING_HUMAN_REVIEW
approval: "Heredada de SE-396: Operadora 2026-09-09 y continuidad 2026-09-21"
parent: SE-396
slice: I03
risk: L2
developer_type: agent-single
---

# SE-396 I03 — Deadline, cancelación y efecto ambiguo

## Objetivo

Cerrar el límite de ejecución iniciado en I01: una ejecución que excede su
presupuesto o lanza una excepción después de adquirir la reserva nunca se
reintenta automáticamente ni se convierte en éxito por una respuesta tardía.

## Contrato

1. `ExecutionRequest.deadline_ms` es un presupuesto relativo medido con reloj
   monotónico desde inmediatamente antes de invocar `adapter.execute`.
2. El runtime invoca `adapter.execute(request)` una sola vez en un worker daemon
   y espera como máximo `deadline_ms`.
3. Si termina dentro del plazo, se conserva la validación y commit atómico de
   I01. Un resultado inválido conserva la reserva.
4. Si vence el plazo, el runtime solicita `adapter.cancel(request_id)` exactamente
   una vez, de forma best-effort y no bloqueante. La respuesta de `cancel` no
   demuestra que el efecto se haya detenido o revertido.
5. Timeout, excepción de `execute` o resultado tardío producen
   `AMBIGUOUS_EXECUTION`. La reserva permanece durable y bloquea todo retry,
   incluso tras reabrir el store.
6. Un resultado que llega después del timeout se descarta: no escribe journal,
   no completa call y no libera la reserva.
7. Esta slice no añade una operación pública `cancel`, no eleva autoridad y no
   promete exactly-once para efectos externos.

## Archivos permitidos

- `scripts/dual-cli/runtime.py`
- `tests/dual-cli/test_runtime.py`
- `docs/specs/SE-396-i03-deadline-cancel.spec.md`
- Registro de avance de la spec padre y CHANGELOG fragment al cerrar.

## Escenarios de aceptación

### AC-I03-01 — timeout fail-closed

Given un adapter que no termina dentro de `deadline_ms`, when el runtime agota
el plazo, then devuelve `AMBIGUOUS_EXECUTION`, solicita cancelación una vez y
mantiene una reserva.

### AC-I03-02 — resultado tardío descartado

Given la ejecución anterior, when el adapter termina después del timeout, then
no aparece decisión en journal y la reserva continúa retenida.

### AC-I03-03 — retry/restart no duplica

Given una reserva ambigua, when se repite el evento con el runtime actual o con
un store reabierto, then `execute` no vuelve a invocarse.

### AC-I03-04 — excepción ambigua

Given un adapter que lanza durante `execute`, when el runtime procesa el evento,
then normaliza el fallo a `AMBIGUOUS_EXECUTION`, conserva la reserva y no reintenta.

### AC-I03-05 — camino rápido intacto

Given un adapter que devuelve antes del plazo, when el resultado es válido,
then se confirma una sola vez y el replay devuelve la misma decisión.

## Verificación

Test rojo dirigido antes de tocar runtime; después, suite completa
`tests/dual-cli`, CI local, diff-check y revisión humana E1. La evidencia es
local/integration hasta merge y no gradúa SE-396.
