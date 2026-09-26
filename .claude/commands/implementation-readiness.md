---
name: implementation-readiness
description: Gate previo a codificar — verifica que una spec esta lista para implementacion con veredicto ternario PASA/RESERVAS/FALLA (SE-269 S2)
model_tier: mid
context_cost: low
tier: core
---

Verificar preparacion pre-implementacion de una spec con veredicto ternario.

## Flujo

1. Ejecutar: `bash scripts/implementation-readiness.sh <spec-file>`
2. Parsear JSON de salida con veredicto + dimensiones
3. Si FALLA: mostrar dimensiones fallidas y motivo; no avanzar
4. Si RESERVAS: mostrar reservas por dimension; registrar follow-up con dueno; permitir avanzar CON advertencia
5. Si PASA: confirmar preparacion completa

## Semantica del veredicto

- **PASA**: todas las dimensiones superadas. La spec esta lista para codificar.
- **RESERVAS**: puede avanzar, pero hay deuda registrada. Cada reserva genera un follow-up con dueno. Si la reserva sigue abierta al cierre de la spec, aparece en el archivo (SE-258 S4).
- **FALLA**: no se puede codificar. La spec tiene deficiencias bloqueantes.

## Restriccion dura (AC-2.2)

Los gates de seguridad, confidencialidad y linea_roja NO admiten RESERVAS. Este comando opera en el dominio de JUICIO (preparacion de spec). Si se intenta usar RESERVAS desde un gate de frontera, ternary-verdict.sh lo rechaza con CRIT-023.

## Auditoria de ratio (AC-2.5)

El script escribe en output/ternary-ratio-audit.jsonl. Si >70% de los ultimos 100 veredictos son RESERVAS, se emite warning de binario cobarde.
