---
name: cache-analytics
description: Métricas de hit rate, tokens ahorrados, latencia, ahorro de costes
developer_type: all
agent: none
context_cost: high
model_tier: fast
tier: core
---

# /cache-analytics

> 🦉 Savia muestra el dashboard de caché — hit rate, ahorros, tendencias.

---

## Cargar perfil de usuario

Grupo: **Context Engineering** — cargar:

- `identity.md` — para aislar métricas por usuario

Ver `docs/rules/domain/context-map.md`.

---

## Parámetros

```
--period week|month     Período de análisis (por defecto: week)
--export               Exportar a CSV/JSON
--lang es|en           Idioma del output
```

---

## Flujo

### Paso 1 — Leer métricas de caché

1. Leer logs de cache hits: `$HOME/.pm-workspace/cache-metrics.jsonl`
   - Formato: timestamp, layer, hit/miss, tokens_saved, latency_ms
2. Si no existe → informar que el tracking no está activo
3. Filtrar por período (--period week | month)

### Paso 2 — Calcular métricas

**Hit Rate** (% of cache hits):
- Fórmula: hits / (hits + misses)
- Por capa: tools, system, rag, conversation
- Tendencia: semana anterior vs. semana actual

**Tokens Ahorrados**:
- Suma de tokens_saved por período
- Comparar con tokens sin caché (estimado)
- Proyectar ahorro mensual/anual

**Latencia**:
- Promedio latency_ms para hits vs. misses
- Mejora estimada por hit

**Cost Savings**:
- Tokens ahorrados × $0.00001 por token (estimado)
- Mostrar en $ y en % de ahorro

### Paso 3 — Generar dashboard

```
📊 Cache Analytics — Última Semana

Hit Rate Global: 71.3% 📈 (↑5.2% desde semana anterior)

Por Capa:
├─ Tools:       78% hit rate | 450 tokens ahorrados
├─ System:      65% hit rate | 320 tokens ahorrados
├─ RAG:         72% hit rate | 280 tokens ahorrados
└─ Conversation: 68% hit rate | 190 tokens ahorrados

Resumen:
├─ Total tokens ahorrados: 1,240
├─ Latencia mejorada: 2.3x promedio
└─ Cost savings: $0.012 (12 mil tokens × $0.001/1M)

Tendencias (últimas 4 semanas):
├─ Hit rate: ↑ 62% → 71.3% (mejora sostenida)
├─ Tokens: 920 → 1,240 (cache crece)
└─ Latencia: 85ms → 120ms (ligeramente lenta)
```

### Paso 4 — Identificar cache misses

Top 5 misses (comandos que siempre cachean):
- Mostrar comando
- % de misses
- Sugerencia: ¿warm-up automático?

Ejemplo:
```
🔍 Cache Misses Principales

1. /sprint-status      — 28% miss rate (¿warm-up diario?)
2. /my-sprint          — 22% miss rate (¿pre-cargar por rol?)
3. /risk-predict       — 19% miss rate (poco frecuente)
4. /backlog-prioritize — 15% miss rate (fine, poco usado)
```

### Paso 5 — Exportar datos (--export)

Si `--export`: guardar en `output/cache-analytics-{YYYYMMDD}.{csv|json}`:
- Tabla: timestamp, command, layer, hit/miss, tokens, latency
- Resumen: métricas agregadas
- Recomendaciones

---

## Validación

- ✅ Período válido (week, month)
- ✅ Datos al menos 24h (sino: insuficientes)
- ✅ Métricas coherentes (hit rate 0-100%)
- ✅ Export válido (CSV o JSON bien formado)

---

## Restricciones

- Datos agregados por usuario — nunca mostrar datos de otros
- Métricas estimadas, no de facturación real

