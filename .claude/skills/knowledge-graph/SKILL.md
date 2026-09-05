---
layer: peripheral
name: knowledge-graph
description: Usar cuando se construye o consulta el grafo de conocimiento de entidades del proyecto.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: communication
  savia.consumes: workspace_files
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: medium
  savia.produces: graph_db
  savia.summary: "Construye grafos de conocimiento de entidades PM y sus relaciones. Stakeholders, componentes, decisiones, dependencias. Consulta en lenguaje natural. Output: grafo Mermaid."
  savia.tags: "knowledge-graph, entities, relations, queries"
  savia.trigger_keywords: "grafo, knowledge graph, entidades, relaciones, kg"
---

# Skill: knowledge-graph

> Grafo de entidades y relaciones PM. Almacenamiento persistente en JSONL. Consultas en lenguaje natural.

## Concepto

Un grafo de conocimiento PM conecta 8 tipos de entidades (Project, PBI, Task, Member, Skill, Risk, Decision, Sprint) a través de 7 tipos de relaciones. Almacenado en JSONL para durabilidad. Soporta consultas en lenguaje natural que se traducen a traversals de grafo.

## Entidades

| Tipo | Descripción | Atributos clave |
|---|---|---|
| **Project** | Proyecto PM | nombre, descripción, equipo, estado |
| **PBI** | Product Backlog Item | ID, título, descripción, estado, storypoints |
| **Task** | Tarea técnica | ID, descripción, estimación, estado, dueña |
| **Member** | Miembro del equipo | nombre, skills, capacidad, disponibilidad |
| **Skill** | Habilidad técnica | nombre, nivel (junior/mid/senior), demanda |
| **Risk** | Riesgo identificado | descripción, probabilidad, impacto, mitigación |
| **Decision** | Decisión arquitectónica | descripción, fecha, ADR ref, rationale |
| **Sprint** | Ciclo de trabajo | número, fechas, capacidad, velocity |

## Relaciones

| Tipo | Desde | Hacia | Significado |
|---|---|---|---|
| **HAS_PBI** | Project | PBI | El proyecto contiene este PBI |
| **DECOMPOSES_TO** | PBI | Task | El PBI se descompone en estas tareas |
| **ASSIGNED_TO** | Task | Member | La tarea está asignada a este miembro |
| **HAS_SKILL** | Member | Skill | El miembro domina esta habilidad |
| **HAS_RISK** | Task | Risk | Esta tarea enfrenta este riesgo |
| **AFFECTS** | Decision | Task | Esta decisión impacta esta tarea |
| **CONTAINS** | Sprint | Task | Este sprint contiene estas tareas |

## Almacenamiento

**Ubicación:** `data/knowledge-graph/{proyecto}.jsonl`

**Formato JSONL (una entidad por línea):**
```json
{"type":"Project","id":"sala-reservas","name":"Sala Reservas","team":["Alice","Bob"]}
{"type":"PBI","id":"AB#1234","title":"API Reservas","status":"active","project":"sala-reservas"}
{"type":"Task","id":"AB#1234.1","title":"Diseñar endpoints","assigned":"Alice","sprint":"2026-04"}
{"type":"Member","id":"alice","name":"Alice","skills":["TypeScript","API"]}
{"type":"Skill","id":"typescript","name":"TypeScript","level":"mid"}
{"type":"Risk","id":"R001","desc":"Delay BD","prob":0.4,"impact":5}
{"type":"Decision","id":"ADR-001","desc":"GraphQL","adr":"projects/adr/ADR-001.md"}
{"type":"Sprint","id":"2026-04","number":"2026-04","capacity":80}
```

## Construcción (fuentes)

El grafo se construye escaneando:
1. **Azure DevOps** — work items, iteraciones, asignaciones, capacidades
2. **equipo.md** — miembros, skills, roles
3. **reglas-negocio.md** — decisiones, restricciones, riesgos
4. **agent-notes** — contexto acumulado, decisiones, hallazgos

## Consultas

Traduce preguntas en lenguaje natural a graph traversals:

| Pregunta | Traversal | Ejemplo |
|---|---|---|
| "¿Quién sabe TypeScript?" | Member→HAS_SKILL→Skill | Alice, Bob (senior), Charlie (junior) |
| "¿De qué depende Task #123?" | Task←DECOMPOSES_TO←PBI | PBI AB#456: "Migrar BD" |
| "¿Qué riesgos afectan a este sprint?" | Sprint→CONTAINS→Task→HAS_RISK | R001: "Delay", R004: "API down" |
| "¿Impacto de cambiar decisión ADR-5?" | Decision→AFFECTS→Task | Tasks AB#123, AB#124, AB#125 |
| "¿Capacidad de Alice el próximo sprint?" | Member→(ASSIGNED_TO←Task←CONTAINS) | 32/80 SP asignados en Sprint 2026-05 |

## Máximo 130 líneas

Documentación comprimida. Detalles de implementación en comandos `/graph-*`.
