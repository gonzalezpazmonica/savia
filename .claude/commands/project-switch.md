---
name: project-switch
description: Cambia el proyecto activo de Savia para aislamiento de contexto (SE-093).
model_tier: fast
context_cost: low
tier: core
---

# /project-switch

**Argumentos:** `$ARGUMENTS` — nombre del proyecto a activar, o vacío para mostrar el activo actual.

## 1. Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 /project-switch — Cambio de proyecto activo
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Sin argumentos: mostrar estado

Si `$ARGUMENTS` está vacío:

1. Ejecutar `bash scripts/project-context.sh detect` y mostrar el proyecto actual.
2. Ejecutar `bash scripts/project-context.sh list` y mostrar disponibles.
3. Sugerir: "Usa `/project-switch <nombre>` para cambiar."
4. Terminar (exit 0).

## 3. Validar proyecto solicitado

1. Comprobar que `$ARGUMENTS` aparece en `bash scripts/project-context.sh list`.
2. Si no existe:
   - Mostrar error: `❌ Proyecto '$ARGUMENTS' no encontrado.`
   - Listar disponibles.
   - Terminar (exit 1).

## 4. Cambiar proyecto activo

1. Ejecutar `bash scripts/project-context.sh set "$ARGUMENTS"`.
2. Verificar que `bash scripts/project-context.sh detect` devuelve `$ARGUMENTS`.
3. Si falla, mostrar el error de set y abortar.

## 5. Resumen del proyecto

Mostrar mini-dashboard del proyecto recién activado:

- **Nombre**: `$ARGUMENTS`
- **CLAUDE.md**: si `projects/$ARGUMENTS/CLAUDE.md` existe → mostrar primera línea
- **Último sprint**: si `projects/$ARGUMENTS/sprints/` existe → último subdirectorio
- **Issues activos**: si `projects/$ARGUMENTS/issues/` existe → contar `*.md`
- **Recordatorio**: las próximas respuestas usarán este proyecto como contexto activo

## 6. Output final

```
✅ Proyecto activo: $ARGUMENTS
   Las siguientes interacciones se aislarán a este proyecto.
   project-isolation-gate.sh emitirá WARNING ante referencias cruzadas.
```

## Notas

- No bloquea acceso a otros proyectos — solo cambia el foco de Savia.
- El estado se persiste en `.savia/active-project` (gitignored).
- Para limpiar: `bash scripts/project-context.sh clear`.
- Referencias: `docs/rules/domain/zero-project-leakage.md`, SE-093.
