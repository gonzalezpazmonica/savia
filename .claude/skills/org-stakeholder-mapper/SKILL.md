---
layer: peripheral
name: org-stakeholder-mapper
description: "Mapeador de Stakeholders y Decisores: extrae roles formales y reales, motivaciones, alianzas y tensiones de una organización."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: org-intelligence
  savia.maturity: stable
  savia.context: fork
  savia.context_cost: medium
  savia.context_tier: L3
  savia.maturity: stable
  savia.summary: Produce YAML de nodos + narrativa markdown del mapa de stakeholders. NUNCA escribe al grafo sin aprobación humana.
  savia.tags: "stakeholders, org-intelligence, poder, decisores, análisis-organizativo"
  savia.trigger_keywords: "stakeholders, mapa de poder, decisores, quién decide, alianzas, quién apoya"
---

# Skill: Org Stakeholder Mapper

Extrae y estructura el mapa de stakeholders de una organización a partir de información
disponible (entrevistas, organigramas, transcripciones, observación directa).

## Cuándo usarlo

- Antes de una iniciativa que requiera alineamiento multi-departamental
- Cuando no está claro quién decide realmente vs. quién firma
- Para identificar aliados naturales y focos de resistencia
- Antes de proponer cambios que afectan a varios departamentos o niveles

## Inputs requeridos

| Campo | Descripción |
|---|---|
| `personas` | Lista de personas conocidas: nombre, cargo formal, departamento |
| `iniciativa` | Descripción breve de la iniciativa o proyecto a analizar |
| `fuente` | Tipo de fuente: orgchart / entrevista / transcripción / observación |
| `contexto` | Información adicional relevante sobre la organización |

## Output producido

1. **YAML de nodos**: cada stakeholder con `nombre`, `cargo_formal`, `rol_real`,
   `motivacion`, `postura`, `intensidad`, `confidence`
2. **Narrativa markdown**: análisis de alianzas, tensiones y centros de poder
3. **Campos pendientes**: lista de lo que falta para completar el mapa

## Restricciones absolutas

- NUNCA escribe al grafo de conocimiento sin aprobación humana explícita
- Toda inferencia lleva `confidence: INFERRED` — nunca se presenta como hecho
- Datos personales sensibles: nivel mínimo N3 de confidencialidad
- No incluir especulaciones sobre motivaciones personales no laborales
- Si la información es insuficiente, documenta las lagunas — no inventa

## Ejemplo de invocación

```
/skill org-stakeholder-mapper
personas: ["Ana García (CTO)", "Luis Mora (Dir. Operaciones)", "Elena Ramos (CFO)"]
iniciativa: "Implementar nuevo ERP en 6 meses"
fuente: transcripción de kick-off
contexto: empresa manufacturera 200 empleados, reciente cambio de CEO
```

## Relación con otros skills

- **Upstream**: `org-meeting-capture` proporciona personas y señales detectadas
- **Downstream**: `org-political-landscape` consume el mapa para análisis político
- **Protocolos**: `docs/rules/domain/org-intelligence-protocol.md` — TTL, confidencialidad
