---
name: spec-implement
description: Implementa una Spec según su developer_type — lanza agente o asigna a humano.
model_tier: heavy
context_cost: high
tier: core
---

# /spec-implement

Implementa una Spec según su `developer_type`: lanza agente o asigna a humano.

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **SDD & Agentes** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/workflow.md`
   - `profiles/users/{slug}/projects.md`
3. Adaptar output según `identity.rol` (tech lead vs PM), `workflow.reviews_agent_code`, `workflow.specs_per_sprint`
4. Si no hay perfil → continuar con comportamiento por defecto

## 2. Uso
```
/spec-implement {spec_file} [--dry-run] [--override-type human|agent-single|agent-team]
```

## 3. Protocolo

### 3.1 Validar Spec

Verificar criterios mínimos antes de implementar:
- `developer_type` definido (no vacío ni "?")
- Sección 2: interfaces con tipos concretos
- Sección 3: reglas sin "TBD" ni "a criterio del dev"
- Sección 4: al menos un test scenario
- Sección 5: ficheros con rutas exactas
- Sección 6: al menos un fichero de referencia
- Estado: "Pendiente"

Si falla → informar problemas y sugerir `/spec-review`.

### 2. Ejecutar según developer_type

**human** → Informar asignado + task ID. Ofrecer: notificar al dev o mover task a "Active".

**agent-single** → Mostrar plan (spec, modelo opus, log, max turns 40) → confirmar → lanzar agente con system-prompt del proyecto, instrucciones de implementar Spec exactamente, detenerse ante ambigüedad, ejecutar build+test (máx 3 reintentos). Log en `output/agent-runs/`.

**agent-team** → Leer team pattern de la spec (default: `impl-test`) → confirmar → lanzar Implementador (opus) + Tester (haiku) en paralelo. Si pattern incluye review, lanzar Reviewer después.

### 3. Post-implementación (solo agentes)

Actualizar task en Azure DevOps: estado → "In Review", tags → "spec-driven;agent-implemented", historial con referencia al log.

**Reviewer por asignación de tarea:** Si la task tiene un `System.AssignedTo` humano, añadir a ese programador como reviewer del PR. Esto aplica tanto a implementaciones por agente como a PRs creados manualmente desde una tarea DevOps.

## Restricciones

- Implementación por agente SIEMPRE requiere Code Review humano antes de merge
- Usar `/spec-review {spec_file}` para pre-check automático antes del review humano
