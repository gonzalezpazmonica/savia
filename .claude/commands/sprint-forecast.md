---
name: sprint-forecast
description: Predicción de completitud del sprint basada en velocity histórica
developer_type: agent-single
agent: azure-devops-operator
context_cost: medium
model_tier: mid
tier: core
---

# Sprint Forecast

## 1. Cargar perfil de usuario

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Sprint & Daily** del context-map):
   - `profiles/users/{slug}/identity.md`
   - `profiles/users/{slug}/workflow.md`
   - `profiles/users/{slug}/projects.md`
   - `profiles/users/{slug}/tone.md`
3. Adaptar output según `tone.alert_style` y `workflow.daily_time`
4. Si no hay perfil → continuar con comportamiento por defecto

## 2. Descripción
Predice la fecha de completitud del sprint actual y items en riesgo usando análisis de velocity histórica con simulación Monte Carlo simplificada.

## 3. Uso
```bash
claude sprint-forecast [sprint-name]
```

## 4. Funcionalidades

### 1. Extracción de Velocity Histórica
- Lectura de últimas 3-5 sprints completadas
- Extracción de story points completados por sprint
- Fuente: Azure DevOps API (WIQL)
- Fallback: datos mock si no hay conexión

### 2. Análisis Estadístico
- Media aritmética de velocity
- Desviación estándar
- Rango de variación (min-max)

### 3. Simulación Monte Carlo
- N=1000 iteraciones
- Cada iteración: selecciona velocity aleatoria del histórico
- Acumula story points hasta alcanzar total de items restantes
- Genera distribución de fechas posibles

### 4. Predicción de Completitud
- Intervalo de confianza 70% (P70)
- Intervalo de confianza 85% (P85)
- Intervalo de confianza 95% (P95)
- Fecha más probable (P50)

### 5. Análisis de Riesgo
- Items con riesgo de no completarse
- Factores que impactan velocity
- Recomendaciones de acción

## Salida

```
╔════════════════════════════════════════════════════════════╗
║          SPRINT FORECAST - [Nombre Sprint]                ║
╚════════════════════════════════════════════════════════════╝

📊 VELOCITY HISTÓRICA
┌────────┬───────────┬──────────────┐
│ Sprint │ Velocity  │ Observación  │
├────────┼───────────┼──────────────┤
│ S-45   │ 34 pts    │ ✓            │
│ S-46   │ 38 pts    │ ✓            │
│ S-47   │ 32 pts    │ Vacaciones   │
├────────┼───────────┼──────────────┤
│ Σ Avg  │ 35 pts    │              │
│ σ Dev  │ 2.8 pts   │              │
└────────┴───────────┴──────────────┘

⏰ PRONÓSTICO DE COMPLETITUD
├─ P50 (Más probable)    : 28 Feb 2026
├─ P70 (70% confianza)   : 02 Mar 2026
├─ P85 (85% confianza)   : 05 Mar 2026
└─ P95 (95% confianza)   : 09 Mar 2026

📋 ESTADO ACTUAL
├─ Items completados     : 12/28
├─ Story points restantes: 58 pts
└─ Sprints para completar: ~1.7 sprints

⚠️  ITEMS EN RIESGO
├─ FEAT-1234 (13 pts) - Alta complejidad
├─ BUG-567 (5 pts)   - Bloqueado por FEAT-1234
└─ DEBT-89 (8 pts)   - Dependencia externa

💡 RECOMENDACIONES
├─ Desbloquear FEAT-1234 antes del 01 Mar
├─ Considerar scope reduction si timeline es crítica
└─ Validar disponibilidad del equipo próxima semana

╚════════════════════════════════════════════════════════════╝
```

## Prerrequisitos
- Conexión a Azure DevOps (vía PAT_FILE)
- Sprint actual en ejecución
- Histórico de al menos 3 sprints previos

## Variables de Entorno
- `$PAT_FILE`: Ruta a archivo con Personal Access Token
- `$AZURE_DEVOPS_ORG`: Organización Azure DevOps
- `$AZURE_DEVOPS_PROJ`: Proyecto Azure DevOps
