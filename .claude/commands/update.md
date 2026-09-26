---
name: update
description: Comprobar y aplicar actualizaciones de pm-workspace desde GitHub, preservando datos locales
developer_type: all
agent: none
context_cost: low
model_tier: fast
tier: core
---

# /update {subcommand}

> 🦉 Savia se mantiene al día — comprueba si hay nuevas versiones y las aplica sin tocar tus datos.

---

## Cargar perfil de usuario

Grupo: **Memory & Context** — cargar `identity.md` + `preferences.md` del perfil activo.
Ver `.claude/profiles/context-map.md`.

## Prerequisitos

- `gh` CLI instalado y autenticado (para consultar GitHub releases)
- Conexión a internet (para check y install)
- Repositorio clonado desde GitHub (origin configurado)

## Subcomandos

### `/update` o `/update check`

Comprueba si hay actualizaciones disponibles:

1. Obtiene versión local (`git describe --tags`)
2. Consulta última release en GitHub (`gh api`)
3. Compara versiones
4. Si hay actualización → muestra versión disponible y notas de release
5. Si ya está actualizado → confirma que todo está al día

Equivale a: `bash scripts/update.sh check`

Voz de Savia (humano): "Estás en la v0.35.0 y la última es la v0.36.0. ¿Quieres que la instale? Tus datos están a salvo."
Voz de Savia (agente): responder en YAML:

```yaml
status: UPDATE_AVAILABLE  # o UP_TO_DATE
current_version: "v0.35.0"
latest_version: "v0.36.0"
changelog_url: "https://github.com/gonzalezpazmonica/pm-workspace/releases/tag/v0.36.0"
```

### `/update install`

Aplica la actualización tras confirmación del usuario:

1. **Verificar datos protegidos** — confirma que profiles, projects, output están en .gitignore
2. **Verificar rama** — si no está en main, cambiar (con aviso)
3. **Stash cambios locales** — `git stash` si hay cambios no committed
4. **Fetch + merge** — `git fetch --tags origin` → `git merge {tag}` (fast-forward preferido)
5. **Restaurar stash** — `git stash pop` si se guardaron cambios
6. **Validar integridad** — verifica que el workspace sigue funcional
7. **Resumen** — versión anterior → nueva, datos intactos

Equivale a: `bash scripts/update.sh install`

**NUNCA ejecutar install sin confirmación explícita del usuario.**

Si hay conflicto de merge → abortar, restaurar stash, notificar al usuario con instrucciones manuales.

### `/update auto-on`

Activa la comprobación automática semanal al iniciar sesión:

1. Escribe `auto_check=true` en `$HOME/.pm-workspace/update-config`
2. Confirma activación

Equivale a: `bash scripts/update.sh config auto_check true`

### `/update auto-off`

Desactiva la comprobación automática:

1. Escribe `auto_check=false` en `$HOME/.pm-workspace/update-config`
2. Confirma desactivación
3. Recuerda que `/update check` sigue disponible manualmente

Equivale a: `bash scripts/update.sh config auto_check false`

### `/update status`

Muestra estado completo del sistema de actualizaciones:

- Versión actual
- Auto-check activado/desactivado
- Última comprobación (fecha y hace cuántos días)
- Intervalo configurado
- Ruta del fichero de configuración

Equivale a: `bash scripts/update.sh status`

## Datos protegidos

Estos ficheros y directorios NUNCA se ven afectados por una actualización:

- `.claude/profiles/users/*/` — perfiles de usuario (gitignored)
- `projects/*/` — datos de proyectos (gitignored)
- `output/` — informes y artefactos generados (gitignored)
- `CLAUDE.local.md` — configuración local (gitignored)
- `decision-log.md` — registro de decisiones (gitignored)
- `.claude/rules/pm-config.local.md` — config privada (gitignored)

## Restricciones

- **NUNCA** aplicar actualización sin confirmación explícita del usuario
- **NUNCA** forzar merge si hay conflictos — abortar y notificar
- **NUNCA** modificar o eliminar datos del usuario durante la actualización
- Si `gh` no está disponible → informar y sugerir instalación
- Si no hay conexión → informar, no fallar silenciosamente
