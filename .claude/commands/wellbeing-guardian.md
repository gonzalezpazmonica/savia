---
name: wellbeing-guardian
description: "Proactive individual wellbeing system — break reminders, after-hours alerts, work-life balance nudges"
allowed-tools: [Read, Glob, Grep, Write, Edit]
argument-hint: "[status|configure|breaks|report|pause] [--reason work|personal|hydration] [--week|--month] [--summary|--detailed]"
model_tier: mid
context_cost: low
tier: core
---

# /wellbeing-guardian — Sistema proactivo de bienestar individual

> Skill: @.opencode/skills/wellbeing-guardian/SKILL.md
> Config: @docs/rules/domain/wellbeing-config.md
> Perfil: @.claude/profiles/users/{slug}/workflow.md

Savia vela por tu salud durante las sesiones de trabajo: recuerda descansos,
alerta fuera de horario y sugiere pausas. Basado en evidencia científica
(HBR 2026, técnica Pomodoro, regla 52-17, método 5-50).

## Subcomandos

### `/wellbeing-guardian status`

Muestra el estado actual de bienestar en la sesión:
- Tiempo de sesión transcurrido
- Estrategia activa y próximo descanso
- Breaks tomados vs esperados
- Barra de progreso visual (🟩⬜)

### `/wellbeing-guardian configure`

Setup interactivo del horario y preferencias de descanso:
1. Horario laboral (inicio, fin, comida, conciliación)
2. Estrategia de breaks (pomodoro, 52-17, 5-50, custom)
3. Umbrales (máximo horas diarias, silencio en fines de semana)

Persiste la configuración en `workflow.md` del perfil activo.

### `/wellbeing-guardian breaks [--week|--month]`

Historial de pausas registradas:
- Sin flag: breaks de la sesión actual
- `--week`: resumen semanal
- `--month`: resumen mensual

Formato: tabla con hora, duración y razón de cada pausa.

### `/wellbeing-guardian report [--summary|--detailed]`

Informe de bienestar:
- `--summary` (default): compliance %, horas totales, recomendación
- `--detailed`: desglose por día, tiempo medio de foco, tendencias

Genera `break_compliance_score` consumible por `/burnout-radar`.

### `/wellbeing-guardian pause [--reason work|personal|hydration|focus-break]`

Registra una pausa voluntaria:
- Marca el momento de pausa
- Categoriza por razón (opcional)
- Al volver, muestra mensaje de bienvenida con duración registrada
- Resetea el contador de foco

## Estrategias disponibles

| Estrategia | Foco | Descanso | Pausa larga |
|---|---|---|---|
| pomodoro | 25 min | 5 min | 20-30 min cada 4 ciclos |
| 52-17 | 52 min | 17 min | — |
| 5-50 | 50 min | 5 min analógico | 15 min cada 3 ciclos |
| custom | configurable | configurable | configurable |

## Nudges automáticos

Savia sugiere descansos de forma amable y no intrusiva:
- **Break debido** → al superar el tiempo de foco configurado
- **Fuera de horario** → al detectar trabajo tras `work_hours_end`
- **Fin de semana** → si `silence_weekends: true` y es sábado/domingo
- **Hidratación** → recordatorios periódicos de agua y postura
- **Post-descanso** → bienvenida al volver de una pausa

Máximo 1 nudge por interacción. Sin bloqueo. El usuario decide siempre.

## Integración

- **burnout-radar**: alimenta `break_compliance_score` individual
- **sustainable-pace**: mejora `wellbeing_factor` con adherencia real
- **daily-routine**: complementa con micro-pausas (no duplica)

## Ejemplo de uso

```
PM: /wellbeing-guardian status
Savia:
⏱️ Sesión actual: 47min
🎯 Estrategia: pomodoro (25min foco / 5min descanso)
📊 Breaks hoy: 1 de 2 esperados
⏭️ Próximo descanso: en 3min
🟩🟩🟩🟩⬜ Progreso hacia próximo break

💡 Llevas 22min de foco continuo. En 3min tu Pomodoro
   sugiere una pausa de 5min. ¿Buen momento?
```

## Primera vez

Si el perfil no tiene campos wellbeing configurados, Savia sugiere
automáticamente `/wellbeing-guardian configure` para el setup inicial.
