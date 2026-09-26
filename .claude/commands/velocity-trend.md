---
name: velocity-trend
description: Tendencia de velocity con media móvil, detección de anomalías y factores explicativos
developer_type: agent-single
agent: azure-devops-operator
context_cost: low
model_tier: mid
tier: core
---

# Velocity Trend Analysis

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
Analiza la tendencia de velocity histórica, detecta anomalías y proporciona factores explicativos para variaciones significativas.

## 3. Uso
```bash
claude velocity-trend [--sprints 8] [--show-factors]
```

## 4. Funcionalidades

### 1. Extracción de Velocity
- Últimos 6-8 sprints completados
- Story points totales por sprint
- Fuente: Azure DevOps (WIQL queries)

### 2. Media Móvil (3-Sprint Moving Average)
- Suaviza fluctuaciones corto plazo
- Fórmula: MA₃ = (V₁ + V₂ + V₃) / 3
- Identifica tendencia subyacente

### 3. Detección de Anomalías
- Umbral: velocity > 1.5 × σ (standard deviation)
- Marca sprints anómalos
- Diferencia entre anómala alta y baja

### 4. Factores Explicativos
- Cambios de equipo (onboarding, departures)
- Períodos vacacionales
- Cambios de scope
- Deuda técnica / refactoring
- Eventos externos (outages, reuniones)

### 5. Análisis de Tendencia
- Dirección: Acelerando ↑ / Estable → / Desacelerando ↓
- Velocidad de cambio
- Predicción para próximo sprint

## Salida

```
╔═══════════════════════════════════════════════════════════╗
║          VELOCITY TREND - Últimos 8 Sprints               ║
╚═══════════════════════════════════════════════════════════╝

📊 VELOCITY POR SPRINT
┌─────────┬──────────┬───────────────┬─────────┐
│ Sprint  │ Velocity │ MA3 (Trend)   │ Status  │
├─────────┼──────────┼───────────────┼─────────┤
│ S-40    │ 32 pts   │ ─             │ ─       │
│ S-41    │ 36 pts   │ ─             │ ─       │
│ S-42    │ 38 pts   │ 35.3 pts      │ ✓       │
│ S-43    │ 40 pts   │ 38.0 pts      │ ✓       │
│ S-44    │ 35 pts   │ 37.7 pts      │ ↑       │
│ S-45    │ 34 pts   │ 36.3 pts      │ ↓       │
│ S-46    │ 28 pts   │ 32.3 pts      │ 🔴 ANOMALÍA
│ S-47    │ 38 pts   │ 33.3 pts      │ ↑ RECUPERA
└─────────┴──────────┴───────────────┴─────────┘

📈 ANÁLISIS ESTADÍSTICO
├─ Promedio (μ)        : 35.1 pts
├─ Desv. Estándar (σ)  : 4.2 pts
├─ Rango               : 28-40 pts
├─ Coeficiente Var.    : 12.0% (Aceptable)
└─ Estabilidad         : MODERADA

⚠️  ANOMALÍAS DETECTADAS

S-46: BAJA ANÓMALA (28 pts)
├─ Desviación : -2.4σ (significativa)
├─ Causa probable : Vacaciones (3 miembros ausentes)
├─ Comparación : -26% vs promedio
└─ Impacto : TEMPORAL

📋 FACTORES EXPLICATIVOS
┌─────────────────────────────────────────┐
│ Sprint │ Factor          │ Impacto     │
├─────────────────────────────────────────┤
│ S-44   │ Onboarding dev  │ -4 pts      │
│ S-46   │ Vacaciones      │ -8 pts      │
│ S-47   │ Equipo completo │ +10 pts     │
└─────────────────────────────────────────┘

📊 TENDENCIA GLOBAL
├─ Dirección             : ESTABLE →
├─ Predicción S-48       : ~36 pts
├─ Confianza             : 80%
└─ Recomendación         : Mantener curso

╚═══════════════════════════════════════════════════════════╝
```

## Prerrequisitos
- Histórico mínimo: 6 sprints completados
- Datos: story points completados por sprint
- Acceso a Azure DevOps API

## Opciones
- `--sprints N`: Analizar últimos N sprints
- `--show-factors`: Mostrar análisis de factores
- `--threshold X`: Personalizar umbral de anomalía (default: 1.5σ)
