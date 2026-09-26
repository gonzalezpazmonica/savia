---
name: spec-design
description: Genera diseño técnico a partir de una spec existente — decisiones, flujo de datos, estrategia de testing.
model_tier: heavy
context_cost: high
tier: core
---

# /spec-design

Genera diseño técnico a partir de una spec existente. Decisiones técnicas, flujo de datos, ficheros a modificar y estrategia de testing.

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
/spec-design {spec-file}
```

- `{spec-file}`: Ruta a fichero spec (ej: `projects/sala-reservas/specs/2026-04/AB1234-B3-create-sala.spec.md`)

## 3. Pasos de Ejecución

### 3.1 — Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 /spec-design — Diseño técnico desde spec
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Paso 2 — Leer spec y exploración previa (si existe)

Cargar:
- Spec file completa
- Si existe `output/explorations/{task-id}-exploration.md` → leerla también

Extraer:
- Sección 2: Contrato (interface, input/output)
- Sección 3: Reglas de negocio
- Sección 4: Test scenarios
- developer_type

### Paso 3 — Lanzar subagente de diseño

Usar `Task` para generar diseño técnico:

**Decisiones técnicas:**
- ¿Por qué este patrón y no otro?
- Alternativas evaluadas
- Trade-offs elegidos

**Flujo de datos:**
- Input: formato, validación
- Processing: pasos, transformaciones
- Output: formato, efectos secundarios

**Ficheros a crear/modificar:**
- Path exacto
- Estimación líneas de código
- Dependencias

**Estrategia de testing:**
- Escenarios unitarios
- Escenarios integración (si aplica)
- Cobertura esperada

**Dependencias y riesgos:**
- Librerías necesarias
- Riesgos identificados
- Mitigaciones

### Paso 4 — Guardar resultado

```
projects/{proyecto}/specs/{sprint}/{task-id}-design.md
```

Formato markdown con secciones: Decisiones | Flujo | Ficheros | Testing | Riesgos

### Paso 5 — Banner de finalización

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ /spec-design — Diseño técnico generado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📄 Diseño: projects/{proyecto}/specs/{sprint}/{task-id}-design.md

Decisiones documentadas ................ ✅
Flujo de datos especificado ............ ✅
Ficheros identificados ................. N
Estimación total ....................... Xh
Riesgos evaluados ...................... N

⚡ /compact — Liberar contexto
```

## Notas

- El diseño NO es código, solo documentación técnica
- Subagente trabaja en contexto aislado
- Output de subagente ≤ 30 líneas resumen en chat
