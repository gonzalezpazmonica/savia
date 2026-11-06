---
name: labour-document-drafter
description: "Redacta documentos laborales (cartas disciplinarias, despido, extinción) con base en ET español. Produce borradores con artículos exactos y marcadores [DATO PENDIENTE]."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: professional-domain/labour
  savia.context: isolated
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Genera borradores de documentación laboral: cartas de despido disciplinario (art. 54-55 ET), despido objetivo (art. 52-53 ET), acuerdos de extinción (art. 49.1.a ET) y comunicaciones colectivas. Señala datos faltantes con [DATO PENDIENTE]. SIEMPRE requiere revisión por graduado social o abogado."
  savia.tags: "laboral, despido, ET, carta-despido, RRHH, ES"
---

# labour-document-drafter — Redactor de Documentación Laboral

## Cuándo usar esta skill

- Al iniciar un procedimiento disciplinario que pueda terminar en despido.
- Para redactar carta de despido disciplinario (art. 54-55 ET).
- Para comunicar un despido objetivo por causas ETOP (art. 52-53 ET).
- Para documentar un acuerdo de extinción mutua (art. 49.1.a ET).
- Para preparar comunicaciones de sanciones graves o muy graves (art. 58 ET).

## Inputs requeridos

| Campo | Descripción | Ejemplo |
|---|---|---|
| `tipo_documento` | Clase de documento a redactar | `carta-despido-disciplinario`, `despido-objetivo`, `acuerdo-extincion` |
| `datos_empleado` | Nombre, categoría, antigüedad, jornada | "Juan García, Técnico Nivel 3, 5 años, jornada completa" |
| `hechos` | Descripción detallada con fecha/hora/lugar | "Falta injustificada el 15/06/2026, turno mañana, centro Madrid" |
| `convenio` | Convenio colectivo aplicable | "Convenio Colectivo de Hostelería de Madrid 2024" |

## Inputs opcionales

| Campo | Descripción |
|---|---|
| `testigos` | Personas que pueden corroborar los hechos |
| `sanciones_previas` | Antecedentes disciplinarios del trabajador |
| `es_representante` | Si el empleado tiene mandato sindical (activa garantía art. 68 ET) |

## Outputs producidos

1. **Borrador del documento** — estructura legal con artículos ET exactos y lenguaje formal
2. **Marcadores [DATO PENDIENTE]** — todos los campos faltantes identificados explícitamente
3. **Checklist de validación** — elementos obligatorios verificados (fecha, lugar, hechos concretos)
4. **Alertas de riesgo** — prescripción, garantías sindicales, vicios formales que causan improcedencia
5. **Disclaimer laboral** — obligatorio al final de cada output

## Outputs excluidos

- Valoración jurídica definitiva sobre la procedencia del despido
- Representación en juicio ni asesoramiento procesal
- Garantía de que el documento supera control judicial

## Garantías especiales (art. 68 ET)

Si `es_representante: true`, la skill BLOQUEA el borrador y emite:

```
ALERTA CRÍTICA: El trabajador tiene mandato de representante sindical.
La omisión de apertura de expediente contradictorio (audiencia previa)
causa NULIDAD del despido (art. 68 ET). Requiere intervención de
abogado laboralista ANTES de cualquier actuación.
```

## Relación con otras skills

- **Upstream**: `labour-conflict-resolver` (análisis previo del conflicto)
- **Downstream**: `labour-convention-analyzer` (verificación de régimen disciplinario del convenio)
- **Paralelo**: `labour-onboarding-offboarding` (documentación complementaria de salida)

## Ver también

- `DOMAIN.md` — marco legal, estructura de documentos, plazos de prescripción
- `prompt.md` — instrucciones de generación para el modelo
- `docs/rules/domain/professional-domain-disclaimer.md` — disclaimer completo
