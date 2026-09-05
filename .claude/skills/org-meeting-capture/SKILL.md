---
layer: peripheral
name: org-meeting-capture
description: "Captura de Conocimiento Tácito de Reunión: extrae decisores, acuerdos informales y señales políticas de transcripciones."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: org-intelligence
  savia.maturity: stable
  savia.context: fork
  savia.context_cost: medium
  savia.context_tier: L3
  savia.maturity: stable
  savia.summary: "Produce insights (EXTRACTED/INFERRED/AMBIGUOUS), nodos propuestos en YAML y alertas. NUNCA escribe al grafo sin aprobación."
  savia.tags: "reuniones, conocimiento-tácito, transcripciones, org-intelligence, acuerdos-informales"
  savia.trigger_keywords: "transcripción, reunión, acuerdos informales, quién dijo qué, captura reunión, señales políticas"
---

# Skill: Org Meeting Capture

Procesa transcripciones de reuniones para extraer conocimiento organizativo tácito:
quién realmente decide, qué se acordó informalmente, qué señales de poder o
tensión son visibles en el lenguaje y la dinámica.

## Cuándo usarlo

- Tras una reunión relevante con múltiples stakeholders
- Cuando hay discrepancia entre lo que se decidió "oficialmente" y lo que pasó
- Para alimentar el mapa de stakeholders con datos frescos y señales débiles
- Cuando se quiere documentar acuerdos que no quedarán en acta formal

## Inputs requeridos

| Campo | Descripción |
|---|---|
| `transcripcion` | Texto completo de la transcripción (VTT, DOCX, texto plano) |
| `participantes` | Lista de asistentes con nombre y cargo |
| `contexto` | Propósito de la reunión, proyecto asociado, antecedentes |
| `stakeholders_previos` | (Opcional) YAML existente del mapa de stakeholders |

## Output producido

1. **Lista de insights**: cada uno con `tipo`, `contenido`, `fuente` (cita textual),
   `confidence: EXTRACTED / INFERRED / AMBIGUOUS`
2. **Nodos propuestos en YAML**: nuevas personas o actualización de roles detectados
3. **Acuerdos informales**: compromisos no escritos mencionados en la reunión
4. **Señales de alerta**: indicios de bloqueo, resistencia pasiva, coaliciones
5. **Preguntas sin resolver**: ambigüedades que requieren seguimiento

## Restricciones absolutas

- NUNCA escribe al grafo de conocimiento sin aprobación humana explícita
- Los nodos YAML son propuestas — se etiquetan como `status: PENDIENTE_APROBACION`
- Citas textuales solo para insights `EXTRACTED` — no inventar paráfrasis como citas
- Nivel mínimo N3 de confidencialidad; N4 si hay datos personales identificables
- No incluir interpretaciones psicológicas sobre individuos

## Relación con otros skills

- **Downstream**: `org-stakeholder-mapper` consume los nodos propuestos
- **Paralelo**: `org-political-landscape` puede recibir los insights como actualización
- **Protocolos**: `docs/rules/domain/org-intelligence-protocol.md`
