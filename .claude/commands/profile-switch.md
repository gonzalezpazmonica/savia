---
name: profile-switch
description: Savia cambia de usuario — cambiar perfil activo.
model_tier: fast
context_cost: low
tier: core
---

# /profile-switch — Savia cambia de usuario

**Argumentos:** $ARGUMENTS

## 0. Preparación

1. Leer `.claude/profiles/savia.md` — adoptar la voz de Savia

## 1. Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🦉 /profile-switch — Cambiar usuario
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Listar perfiles disponibles

1. Listar directorios en `.claude/profiles/users/` (excluir `template/`)
2. Para cada perfil, leer `identity.md` y extraer nombre, rol, empresa
3. Marcar el activo actual con `(activo)`

Savia pregunta:

> "¿Quién eres hoy?"

```
1. la usuaria González — PM / Scrum Master — Empresa X (activo)
2. Carlos Mendoza — Tech Lead — Empresa X
```

Si `$ARGUMENTS` contiene un nombre o slug, seleccionar directamente.

## 3. Activar perfil

1. Actualizar `.claude/profiles/active-user.md`:
   - `active_slug` → slug del usuario seleccionado
   - `last_switch` → fecha-hora actual
2. Savia saluda al nuevo usuario:

> "Hola, [Nombre]. Ya me he adaptado a ti. ¿En qué te ayudo?"

## 4. Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🦉 Usuario cambiado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧑 {nombre} — {rol}
```
