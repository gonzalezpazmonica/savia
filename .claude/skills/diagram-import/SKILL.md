---
layer: peripheral
name: diagram-import
description: Usar cuando se importa un diagrama existente para extraer entidades y crear PBIs.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: business-analyst
  savia.maturity: stable
  savia.category: devops
  savia.context: fork
  savia.context_cost: high
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Importa diagramas (Draw.io, Miro, Mermaid), extrae entidades y genera Features/PBIs en Azure DevOps. Valida reglas de negocio antes de crear work items."
  savia.tags: "diagram-import, parsing, work-items, entities"
---

# Skill: Diagram Import — Parsing, Validación y Generación de Work Items

Importa diagramas de arquitectura (Draw.io, Miro, Mermaid local), extrae entidades y relaciones, valida reglas de negocio y genera Features/PBIs/Tasks en Azure DevOps.

**Principio fundamental:** NO se crean PBIs sin información de reglas de negocio.

---

## Triggers

- Comando `/diagram-import` — Importación completa
- Petición: "importa el diagrama y crea los PBIs"

---

## Contexto Requerido

1. `CLAUDE.md` (raíz) — Contexto global, Azure DevOps
2. `projects/{proyecto}/CLAUDE.md` — Stack, arquitectura
3. `projects/{proyecto}/reglas-negocio.md` — **CRÍTICO**
4. `projects/{proyecto}/equipo.md` — Perfiles para asignación
5. `docs/rules/domain/diagram-config.md` — Constantes
6. `docs/politica-estimacion.md` — Rangos de estimación

---

## Fase 1: Obtener y Parsear

### 1.1 Fuentes soportadas

| Fuente | Detección | Método |
|---|---|---|
| Draw.io | `draw.io/` en URL | MCP `draw-io` → XML |
| Miro | `miro.com/app/board/` | MCP `miro` → JSON |
| Local `.drawio` | Extensión | Leer XML directo |
| Local `.mermaid` | Extensión | Parsear Mermaid |
| Meta existente | `diagrams/*.meta.json` | Leer meta |

### 1.2 Modelo normalizado

```json
{
  "entities": [{"id": "svc-users", "type": "microservice", "name": "User Service"}],
  "relationships": [{"from": "api-gateway", "to": "svc-users", "type": "http-sync"}]
}
```

### 1.3 Reconocimiento de shapes

Rectángulos→servicios, Cilindros→DBs, Hexágonos→colas, Rombos→decisiones, Redondeados→frontends, Grises/dashed→externos.

---

## Fase 2: Validación Arquitectónica

Invocar `diagram-architect` para:
1. Detectar ciclos de dependencias
2. Validar layering correcto
3. Identificar antipatrones
4. Evaluar completitud

Si problemas ❌ → informar al PM.

---

## Fase 3: Validación de Reglas de Negocio (CRÍTICO)

### 3.1 Cargar reglas

Leer `projects/{proyecto}/reglas-negocio.md`. Si no existe:
```
❌ Falta reglas-negocio.md

Necesito: projects/{proyecto}/reglas-negocio.md
¿Genero plantilla para completar?
```

### 3.2 Verificar por entidad

Checklist por tipo: **`references/templates-and-examples.md`**

| Tipo | Campos |
|---|---|
| Microservicio | Interfaz, schema DB, entorno, escalado |
| API | Método, path, auth, rate limit, validaciones |
| BD | Tecnología, schema, backup, escalado, retención |
| Frontend | User stories, accesibilidad, responsive |
| Cola | Formato, reintentos, DLQ, orden |
| Integración | Proveedor, SLA, fallback, credenciales, formato |

### 3.3 Opciones si falta info

Ver **`references/templates-and-examples.md`** — "Manejo de Información Faltante"

---

## Fases 4-7: Generación y Creación

Detalles sobre agrupación en Features, generación de PBIs, presentación, y creación en Azure DevOps.

Ver: **`references/templates-and-examples.md`**

- Fase 4: Agrupación, generación PBIs, estimación
- Fase 5: Presentar propuesta al PM
- Fase 6: Crear en Azure DevOps
- Fase 7: Resumen final

---

## Referencias

→ Templates & ejemplos: `references/templates-and-examples.md`
→ Domain mapping: `references/diagram-to-domain-mapping.md`
→ Business rules: `references/business-rules-validation.md`
→ Config: `@docs/rules/domain/diagram-config.md`
