---
layer: peripheral
name: wellbeing-guardian
description: Usar cuando se monitorizan señales de bienestar individual en el equipo.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: communication
  savia.maturity: stable
  savia.context_cost: low
  savia.dependencies: 
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Sistema proactivo de bienestar: recordatorios de descanso, alertas fuera de horario, nudges de work-life balance. Configurable por usuario. No bloquea, solo sugiere."
  savia.tags: "wellbeing, burnout, sustainable-pace, team-health"
---

# Skill: Wellbeing Guardian

> Regla: @docs/rules/domain/wellbeing-config.md
> Perfiles: @.claude/profiles/users/{slug}/workflow.md + preferences.md

## Prerequisitos

- Perfil de usuario con campos wellbeing configurados en `workflow.md`
- Timezone definido en `preferences.md`

## Flujo: Inicio de sesión

1. Leer `workflow.md` → extraer work_hours_start, work_hours_end, break_strategy
2. Leer `preferences.md` → extraer timezone
3. Calcular hora local actual
4. Si fuera de horario → nudge "Fuera de horario" (una vez)
5. Si fin de semana y silence_weekends → nudge "Fin de semana" (una vez)
6. Calcular próximo break según estrategia:
   - pomodoro: 25min desde inicio sesión
   - 52-17: 52min desde inicio sesión
   - 5-50: 50min desde inicio sesión
   - custom: custom_focus_min desde inicio sesión
7. Retornar contexto compacto (~25 tokens):
   `⏱️ Horario: {start}-{end} {tz} | Break: {strategy} {focus}/{break} | Próximo: tras {N}min`

## Flujo: Check periódico

Durante la conversación, verificar periódicamente (máximo cada 25min):

1. Calcular tiempo transcurrido desde último break o inicio
2. Si elapsed ≥ duración_foco de la estrategia:
   - Insertar nudge "Break debido" al final de la respuesta actual
   - Tono amable, nunca imperativo
3. Si hora_actual > work_hours_end (primera vez):
   - Insertar nudge "Fuera de horario"
   - No repetir salvo que el usuario pida continuar explícitamente
4. Si hora_actual entre lunch_break:
   - Sugerir pausa para comer si el usuario sigue activo

Reglas:
- **Máximo 1 nudge por interacción** — no saturar
- **Escalado**: si usuario ignora 3 nudges → reducir a 1 cada 45min
- **Reset**: `/wellbeing-guardian pause` resetea el contador

## Flujo: Configure

1. Preguntar horario laboral:
   - "¿A qué hora empiezas normalmente?" → work_hours_start
   - "¿A qué hora terminas?" → work_hours_end
   - "¿Tienes franja de comida?" → lunch_break
   - "¿Algún horario de conciliación?" → conciliation
2. Presentar estrategias con tabla comparativa (de wellbeing-config.md)
3. Dejar que el usuario elija o configure custom
4. Preguntar umbrales: max_daily_hours, silence_weekends
5. Persistir todo en workflow.md (preservar campos existentes)
6. Confirmar: "✅ Wellbeing Guardian configurado. Tu estrategia: {strategy}"

## Flujo: Status

1. Leer configuración actual de workflow.md
2. Calcular tiempo de sesión actual
3. Calcular breaks tomados (del contexto de sesión)
4. Mostrar:
   ```
   ⏱️ Sesión actual: {elapsed}min
   🎯 Estrategia: {strategy} ({focus}min foco / {break}min descanso)
   📊 Breaks hoy: {count} de {expected} esperados
   ⏭️ Próximo descanso: en {remaining}min
   🟩🟩🟩⬜⬜ Progreso hacia próximo break
   ```

## Flujo: Pause

1. Registrar momento de pausa
2. Si --reason proporcionado → categorizar (work, personal, hydration, focus-break)
3. Mostrar nudge "Post-descanso" cuando el usuario vuelva
4. Resetear contador de foco

## Flujo: Breaks (historial)

1. Mostrar breaks registrados en la sesión actual
2. Si --week: agregar breaks de la semana (si hay log persistente)
3. Formato tabla: hora, duración, razón
4. Calcular break_compliance_score: (tomados / esperados) × 100

## Flujo: Report

1. Leer historial de sesiones (contexto actual + log si existe)
2. Calcular métricas:
   - Horas totales de trabajo
   - Breaks tomados vs esperados (compliance %)
   - Tiempo medio de foco continuo
   - Incidencias fuera de horario
3. Generar break_compliance_score para burnout-radar
4. Presentar resumen + 1-2 recomendaciones personalizadas
5. Si compliance < 60% → sugerir estrategia alternativa

## Errores

| Error | Acción |
|-------|--------|
| Perfil sin wellbeing config | Sugerir `/wellbeing-guardian configure` |
| Timezone no definido | Pedir timezone o asumir UTC |
| Estrategia desconocida | Fallback a pomodoro |
| Sin historial de breaks | Mostrar solo sesión actual |

## Seguridad

- NUNCA registrar contenido de trabajo en logs de bienestar
- Datos de horario → perfil local, nunca en commits públicos
- Respetar `silence_weekends` sin excepciones
- No enviar datos de bienestar a sistemas externos
