---
name: focus-mode
description: Modo single-task — carga una sola tarea y oculta distracciones
model_tier: fast
context_cost: low
allowed_tools: ["Read", "Write"]
tier: core
---

# /focus-mode [opciones]

Reduce el ruido: carga una sola tarea en tu contexto y oculta todo lo demás. Complementa `/guided-work` (focus-mode = entorno limpio, guided-work = guía activa).

## Parámetros

- `--task {PBI-id|spec|descripción}` — La tarea en la que enfocarse
- `--duration {minutos}` — Duración de la sesión de foco (default: del perfil o 25 min)
- `end` — Finalizar modo foco y restaurar contexto normal
- `status` — Ver tarea actual, tiempo restante, progreso

## Flujo

### Activar

1. Cargar la tarea especificada (spec SDD, PBI, o descripción)
2. Cargar SOLO los ficheros relacionados con esa tarea
3. Establecer contexto reducido: ocultar sprint board, backlog, otros proyectos
4. Iniciar temporizador de pausa según `break_interval_min` del perfil
5. Confirmar:

```
🎯 Modo foco activado
  Tarea: [título]
  Duración: [N] min
  Ficheros cargados: [lista breve]

  Solo verás información de esta tarea.
  Para salir: /focus-mode end
```

### Durante el foco

- Si el usuario pide información de otra tarea → "Estás en modo foco. ¿Quieres salir del foco para ver eso, o seguimos con [tarea]?"
- Al cumplir el intervalo de pausa → "Llevas [N] minutos. ¿Quieres tomar un descanso o seguir?"
- Si pide `/guided-work` → activar dentro del foco (se complementan)

### Finalizar

`/focus-mode end` restaura el contexto normal:

```
Modo foco finalizado.
  Tarea: [título]
  Tiempo en foco: [N] min
  [Resumen breve de lo avanzado si es posible]
```

### Status

```
🎯 Modo foco activo
  Tarea: [título]
  Tiempo: [transcurrido] / [duración]
  Próxima pausa sugerida: en [X] min
```

## Integración

- **Con guided-work**: si guided_work=true en el perfil, al activar focus-mode se ofrece automáticamente `/guided-work --task {misma tarea}`
- **Con wellbeing-guardian**: las pausas se coordinan con la configuración de bienestar
- **Con my-focus**: `/my-focus` identifica la tarea más prioritaria; `/focus-mode` crea el entorno limpio para ella

## Restricciones

- NUNCA bloquear al usuario: si insiste en ver otra cosa, permitir con aviso
- No registrar tiempo de foco como imputación automática (eso es decisión del usuario)
- Si la tarea se completa antes del tiempo → celebrar y preguntar si quiere otra o descansar
