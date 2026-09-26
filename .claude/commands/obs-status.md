---
name: obs-status
description: Health check de todas las fuentes de observabilidad conectadas
developer_type: all
agent: task
context_cost: high
model_tier: fast
tier: core
---

# /obs-status

> 🦉 ¿Cómo está la observabilidad? Status de todas las fuentes en un vistazo.

---

## Sintaxis

```
/obs-status [--verbose] [--lang es|en]
```

---

## Flujo

### Paso 1 — Descubrir fuentes conectadas

Leer `.claude/profiles/integrations/obs-*.md`:
- obs-grafana.md → Grafana
- obs-datadog.md → Datadog
- obs-appinsights.md → Azure App Insights
- obs-otel.md → OpenTelemetry Collector
- obs-custom.md → Custom endpoint

### Paso 2 — Health check de cada fuente

Para cada fuente:
1. Test de conectividad (HTTP GET health endpoint)
2. Verificar último sync exitoso
3. Volumen de datos disponible
4. Alertas activas
5. Estado de capacidades (logs, metrics, traces)

### Paso 3 — Detectar problemas críticos

Listar alertas activas que afecten disponibilidad o ingesta de datos.
Marcar: desconexiones, cuota alcanzada, latencias altas, timeouts.

### Paso 4 — Resumen comprimido

```
✅ Observabilidad: SALUDABLE
🟢 Fuentes: 4/5 online
  ├─ Grafana ........... ✅ (3 min ago)
  ├─ Datadog ........... ✅ (1 min ago, ⚠️ cuota 90%)
  ├─ App Insights ...... ✅ (5 min ago)
  └─ OpenTelemetry .... ❌ (offline 2.3h)

⚠️  Alertas activas: 2
💡 Acciones: Reiniciar OTel, monitorear Datadog cuota
```

### Paso 5 — Verbose (si `--verbose`)

Mostrar:
- RTT de cada API
- Timestamps exactos del último sync
- Volumen de datos por tipo
- Ventanas de retención
- Versiones de agentes

---

## Casos especiales

**Fuente desconectada**: explicar razón (proceso muerto, puerto cerrado, auth fallido)
**Cuota alcanzada**: mostrar % utilizado, tendencia, proyección, opciones
**Latencia alta**: marcar si > umbral esperado

---

## Output

Resumen (20–30 líneas) en conversación.
Detalle completo en `output/obs-status-YYYYMMDD.md`.

---

## Integración

- `/obs-connect` → configurar fuente
- `/obs-query` → consultar métrica (solo si fuente saludable)
- `/obs-dashboard` → dashboard por rol (solo fuentes saludables)
- `/emergency-mode` → activar si observabilidad crítica down

