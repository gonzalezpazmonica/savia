---
name: accessibility-mode
description: Toggle rápido de accesibilidad — activa, desactiva o muestra el estado
model_tier: fast
context_cost: low
allowed_tools: ["Read", "Write", "Edit"]
tier: core
---

# /accessibility-mode [acción]

Toggle rápido para gestionar la accesibilidad sin pasar por el wizard completo.

## Parámetros

- `on` — Activa la accesibilidad con los últimos ajustes guardados
- `off` — Desactiva temporalmente (los ajustes se conservan para reactivar)
- `status` — Muestra qué adaptaciones están activas y qué hacen
- `configure` — Permite cambiar un ajuste específico sin repetir todo el setup
- Sin parámetro → equivale a `status`

## Flujo

### Status

Lee `.claude/profiles/users/{slug}/accessibility.md` y muestra:

```
🦉 Accesibilidad — Estado actual

  Visión:
    Lector de pantalla: ✅ activado → sin ASCII art, output estructurado
    Alto contraste: ❌ desactivado

  Motor:
    Acomodación motora: ❌ desactivado

  Cognitivo:
    Carga cognitiva: baja → mensajes cortos, paso a paso
    Trabajo guiado: ✅ nivel alto → Savia pregunta antes de cada paso
    Sensibilidad en reviews: ✅ → lenguaje constructivo

  Bienestar:
    Pausas: Pomodoro cada 25 min

  Para cambiar: /accessibility-mode configure
  Para desactivar todo: /accessibility-mode off
```

### Configure

Pregunta qué ajuste cambiar:

> "¿Qué quieres cambiar? Puedes decirme cosas como 'activa lector de pantalla', 'cambia pausas a 52-17', 'sube la carga cognitiva a media'."

Actualiza solo el campo indicado y confirma.

### On / Off

- `on` → pone todos los campos a sus últimos valores guardados
- `off` → temporalmente desactiva (añade campo `temporarily_disabled: true`)

## Output Template

```yaml
resultado:
  accion: "status|on|off|configure"
  ajustes_activos: [lista]
```

## Restricciones

- Si no existe `accessibility.md` y el usuario ejecuta `status` → sugerir `/accessibility-setup`
- Nunca eliminar el fichero con `off`, solo marcar como temporalmente desactivado
- En `configure`, aceptar lenguaje natural ("quiero que me hables más corto" → cognitive_load: low)
