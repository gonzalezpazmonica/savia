---
name: project-activate
description: "Activa un proyecto como contexto activo en Savia: actualiza active-user.md y crea el directorio de memoria por proyecto si no existe. (SPEC-SE-093-ZERO-LEAK)"
model_tier: fast
context_cost: low
tier: core
---

# /project-activate {name}

**Argumentos:** `$ARGUMENTS` — nombre del proyecto a activar.

## 1. Validar argumentos

Si `$ARGUMENTS` está vacío:
- Mostrar el proyecto activo actual desde `.claude/profiles/active-user.md` (campo `active_project`).
- Listar proyectos disponibles en `projects/`.
- Indicar: "Usa `/project-activate <nombre>` para activar uno."
- Terminar (exit 0).

## 2. Verificar que el proyecto existe

Comprobar que `projects/$ARGUMENTS/` existe en el workspace.

Si no existe:
- Mostrar: `FAIL: Proyecto '$ARGUMENTS' no encontrado en projects/`
- Listar disponibles.
- Terminar (exit 1).

## 3. Actualizar active-user.md (REQ-03)

Editar `.claude/profiles/active-user.md`:
- Si ya existe la línea `active_project:`, actualizar su valor a `$ARGUMENTS`.
- Si no existe, añadir `active_project: "$ARGUMENTS"` al frontmatter YAML antes del cierre `---`.

El fichero resultante debe tener la forma:

```yaml
---
active_slug: "<slug-actual>"
activated_at: "<fecha-actual>"
active_project: "$ARGUMENTS"
---
```

## 4. Crear directorio de memoria del proyecto (REQ-02)

Usar bash para crear el directorio en la ruta de memoria por proyecto si no existe:
`mkdir -p "${HOME}/.savia-memory/projects/$ARGUMENTS"`

## 5. Verificar aislamiento

Ejecutar `bash scripts/project-isolation-check.sh` y mostrar el resultado.

## 6. Output final

```
PASS: Proyecto activo actualizado -> $ARGUMENTS
PASS: directorio de memoria por proyecto creado (o ya existia)
Las siguientes interacciones usaran este proyecto como contexto activo.
```

## Notas

- Lee el proyecto activo desde `.claude/profiles/active-user.md` campo `active_project`.
- El directorio de memoria se crea localmente fuera del repo (gitignored).
- Para verificar aislamiento: `bash scripts/project-isolation-check.sh`
- Ref: SE-093, SPEC-SE-093-ZERO-LEAK
