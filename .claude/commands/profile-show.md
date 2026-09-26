---
name: profile-show
description: Savia muestra tu perfil actual.
model_tier: fast
context_cost: low
tier: core
---

# /profile-show — Savia muestra tu perfil

**Argumentos:** $ARGUMENTS

## 0. Preparación

1. Leer `.claude/profiles/savia.md` — adoptar la voz de Savia
2. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
3. Si no hay usuario activo → Savia dice: "No te tengo registrada/o.
   ¿Empezamos con `/profile-setup`?"

## 1. Banner de inicio

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🦉 /profile-show — Tu perfil
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## 2. Cargar perfil completo

Leer los 6 ficheros del perfil activo:
- `.claude/profiles/users/{slug}/identity.md`
- `.claude/profiles/users/{slug}/workflow.md`
- `.claude/profiles/users/{slug}/tools.md`
- `.claude/profiles/users/{slug}/projects.md`
- `.claude/profiles/users/{slug}/preferences.md`
- `.claude/profiles/users/{slug}/tone.md`

## 3. Mostrar resumen como Savia

Savia presenta el perfil en tono conversacional:

> "[Nombre], esto es lo que sé de ti:
>
> 🧑 **{nombre}** — {rol} en {empresa}
> Desde: {created} | Última actualización: {updated}
>
> 📋 **Tu día a día:** {primary_mode}
>    Daily: {daily_time} | Planning: {planning_cadence}
>    Reporting: {reporting_day} | SDD: {sdd_active}
>
> 🔧 **Herramientas:** {lista}
>
> 📁 **Proyectos:**
>    - {proyecto}: {rol} ({involvement})
>
> ⚙️ **Preferencias:** {language}, detalle {detail_level},
>    informes {report_format}
>
> 💬 **Cómo te hablo:** alertas {alert_style},
>    celebraciones {celebrate}, {formality}
>
> ¿Quieres cambiar algo? → `/profile-edit`"

## 4. Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🦉 Perfil mostrado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✏️ /profile-edit · 🔄 /profile-switch
```
