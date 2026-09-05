---
layer: peripheral
name: org-political-landscape
description: "Análisis de Paisaje Político Interno: detecta tensiones, alianzas y centros de poder a partir de un mapa de stakeholders."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: org-intelligence
  savia.maturity: stable
  savia.context: fork
  savia.context_cost: medium
  savia.context_tier: L3
  savia.maturity: stable
  savia.summary: "Produce mapa político con posturas, intensidades, motivos reales (confidence INFERRED) y condiciones de movimiento."
  savia.tags: "política-organizativa, alianzas, tensiones, poder, org-intelligence"
  savia.trigger_keywords: "paisaje político, tensiones internas, alianzas, centros de poder, resistencia, quién bloquea"
---

# Skill: Org Political Landscape

Analiza el mapa de stakeholders para construir una representación del paisaje
político interno: quién está a favor, quién bloquea, qué coaliciones existen,
qué condiciones cambiarían las posturas.

## Cuándo usarlo

- Cuando hay resistencia difusa a una iniciativa y no está claro su origen
- Antes de presentar una propuesta a dirección para anticipar objeciones reales
- Para diseñar una estrategia de influencia y secuencia de conversaciones
- Cuando el mapa de stakeholders ya existe pero falta la capa política

## Inputs requeridos

| Campo | Descripción |
|---|---|
| `stakeholders_yaml` | Output YAML del skill `org-stakeholder-mapper` |
| `iniciativa` | Descripción de la iniciativa o cambio en análisis |
| `contexto_adicional` | Eventos recientes, cambios de estructura, presupuestos |

## Output producido

1. **Mapa político**: posturas (A FAVOR / NEUTRAL / OPUESTO / DESCONOCIDO),
   intensidades (1–5), coaliciones detectadas, tensiones latentes
2. **Motivos reales inferidos**: con `confidence: INFERRED` explícito
3. **Condiciones de movimiento**: qué necesitaría cambiar para mover a cada actor
4. **Riesgos**: señales de alerta, vetos silenciosos, bloqueos sistémicos
5. **Secuencia de influencia recomendada**: orden de conversaciones

## Restricciones absolutas

- NUNCA escribe al grafo sin aprobación humana explícita
- Todo motivo inferido lleva `confidence: INFERRED` — nunca se presenta como certeza
- Nivel mínimo N3 de confidencialidad en cualquier output
- TTL de 90 días — el mapa político caduca si no se actualiza
- No especular sobre vida personal, salud mental o integridad ética de personas reales

## Relación con otros skills

- **Upstream**: `org-stakeholder-mapper` — mapa base de nodos
- **Paralelo**: `org-meeting-capture` puede actualizar el mapa con señales nuevas
- **Protocolos**: `docs/rules/domain/org-intelligence-protocol.md`
