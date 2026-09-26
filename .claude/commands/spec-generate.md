---
name: spec-generate
description: Genera una Spec ejecutable a partir de una Task de Azure DevOps, lista para implementación.
model_tier: heavy
context_cost: high
tier: core
---

# /spec-generate

Genera una Spec ejecutable (`.spec.md`) a partir de una Task de Azure DevOps, lista para ser implementada por un humano o un agente Claude.

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
/spec-generate {task_id} [--project {nombre}] [--sprint {sprint}] [--force-type human|agent-single|agent-team]
```

- `{task_id}`: ID de la Task en Azure DevOps (ej: `1234`)
- `--project`: Proyecto AzDO (default: `AZURE_DEVOPS_DEFAULT_PROJECT`)
- `--sprint`: Sprint para el directorio de la spec (default: sprint activo)
- `--force-type`: Forzar el developer_type (omitir para usar la matrix automática)

## 3. Este comando orquesta

→ `.opencode/skills/spec-driven-development/SKILL.md`
→ `.opencode/skills/azure-devops-queries/SKILL.md`
→ `references/layer-assignment-matrix.md`
→ `references/spec-template.md`

## Ejemplos

**✅ Correcto:**
```
/spec-generate 1234 --project alpha
→ Lee Task de AzDO, genera projects/alpha/specs/sprint-06/1234-feature-login.spec.md
→ Spec incluye: criterios aceptación, tests, tipo de implementador
```

**❌ Incorrecto:**
```
/spec-generate 1234
→ Generar spec sin leer la Task de AzDO ni validar el proyecto
Por qué falla: La spec sin contexto del PBI genera requisitos inventados
```

## 4. Pasos de Ejecución

### Paso 1 — Leer contexto del proyecto

```bash
# Cargar en orden:
# 1. CLAUDE.md raíz
# 2. projects/{proyecto}/CLAUDE.md  (incluye sdd_layer_assignment)
# 3. projects/{proyecto}/reglas-negocio.md
# 4. .opencode/skills/spec-driven-development/references/layer-assignment-matrix.md
```

### Paso 2 — Obtener la Task de Azure DevOps

Usar skill `azure-devops-queries` para obtener Task completa con campos:
id, title, description, activity, estimated_hours, state, assigned_to,
iteration, tags, parent_url (relación Hierarchy-Reverse).

### Paso 3 — Obtener el PBI padre (criterios de aceptación)

Extraer PBI_ID de parent_url. Obtener: title, description,
acceptance criteria, story_points.

### Paso 4 — Detectar el módulo y buscar código de referencia

```bash
PROYECTO_SOURCE="projects/{proyecto}/source"

# Inferir módulo del título de la task (ej: "B3: Handler CreatePatient" → módulo = "Patient")
MODULE="{módulo inferido del título}"

# Buscar handlers/servicios del mismo tipo como referencia
find $PROYECTO_SOURCE/src -name "*Handler.cs" | grep -i "$MODULE" | head -3
find $PROYECTO_SOURCE/src -name "*${TYPE}*.cs" | head -3  # TYPE = Handler|Service|Repository|Controller

# Leer el fichero de referencia más relevante
# (el agente debe elegir el más similar a lo que se va a implementar)
```

### Paso 5 — Determinar el Developer Type

Aplicar la matrix de `references/layer-assignment-matrix.md`:

1. Extraer la capa y tipo de la Task (ej: "B3: Handler" → Application Layer, Command Handler)
2. Buscar el `developer_type` en la matrix del proyecto (en `projects/{proyecto}/CLAUDE.md § sdd_layer_assignment`)
3. Si no hay override de proyecto, usar la matrix global
4. Si `--force-type` está especificado, usar ese valor

Mostrar al usuario: `Developer Type determinado: agent-single (Application / Command Handler)`

### Paso 6 — Construir la Spec

Usando la plantilla `references/spec-template.md`, rellenar:

- **Sección 1** (Contexto y Objetivo): extraído de la description de la Task + PBI
- **Sección 2** (Contrato Técnico): inferido del título + código de referencia
- **Sección 3** (Reglas de Negocio): extraído de los criterios de aceptación del PBI + `reglas-negocio.md`
- **Sección 4** (Test Scenarios): derivado de los criterios de aceptación
- **Sección 5** (Ficheros a Crear): inferido del tipo de task + módulo + estructura del proyecto
- **Sección 6** (Código de Referencia): el fichero encontrado en el Paso 4
- **Sección 7** (Configuración): constantes del proyecto

### Paso 7 — Guardar la Spec

```bash
# Naming convention: AB{task_id}-{tipo_code}-{descripcion-corta}.spec.md
# Ejemplo: AB1234-B3-create-patient-handler.spec.md

SPEC_DIR="projects/{proyecto}/specs/{sprint}"
mkdir -p $SPEC_DIR
SPEC_FILE="$SPEC_DIR/AB{task_id}-{tipo}-{descripcion-corta}.spec.md"
```

### Paso 8 — Mostrar resumen y preguntar

```
📄 SPEC GENERADA — AB#{task_id}: {título}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Developer Type:  agent-single  (Application / Command Handler)
Fichero:         {spec_file_path}
Estimación:      {Xh}
Asignado a:      {dev o "claude-agent"}

Checklist de calidad:
  ✅ Contrato técnico definido
  ✅ Reglas de negocio especificadas (N reglas)
  ✅ Test scenarios escritos (N scenarios)
  ✅ Ficheros a crear listados (N ficheros)
  ✅ Código de referencia incluido
  ⚠️  {advertencia si algún campo quedó incompleto}

¿Lista? → /spec-implement {spec_file} (agent) o revisar manualmente
```

> ⚠️ La Spec es un BORRADOR. Revisarla antes de implementar. Si tiene {placeholder}, NO está lista.