---
name: review-checkpoint
description: "Genera paquete de revision humana en 5 secciones: cambio, orden de lectura, hallazgos, verificacion manual, cierre (SE-269 S3)"
model_tier: mid
context_cost: low
tier: core
---

Generar paquete de revision humana tras un bounded review del Court.

## Flujo

1. Ejecutar: `bash scripts/review-checkpoint.sh --branch <rama> [--spec <spec-file>]`
2. Leer el paquete generado en `output/review-checkpoints/`
3. Presentar las 5 secciones al revisor humano

## Estructura del paquete

1. **Que cambio y por que** — ligado a la spec/BR de origen
2. **Orden de lectura sugerido** — declarado por el autor (si existe) o generado del diff (etiquetado como tal)
3. **Hallazgos ordenados por preocupacion** — seguridad > rendimiento > logica > estilo. Los ya corregidos NO se listan (AC-3.4)
4. **Verificacion manual** — 2-5 observaciones con resultado esperado. Si no hay comportamiento observable, se declara explicitamente y se emite 0 observaciones (AC-3.3 anti-relleno)
5. **Cierre** — APROBAR | REHACER | SEGUIR DISCUTIENDO

## Integracion con el ciclo acotado

El checkpoint se genera DESPUES del freeze del bounded review (SE-260 S1).
No reabre el bucle de revision.
