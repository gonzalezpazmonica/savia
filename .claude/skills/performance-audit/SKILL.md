---
layer: peripheral
name: performance-audit
description: Usar cuando se audita el rendimiento estático de código para detectar hotspots.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.context_cost: medium
  savia.developer_type: all
  savia.maturity: stable
  savia.priority: medium
  savia.references: "references/perf-dotnet.md, references/perf-typescript.md, references/perf-python.md, references/perf-java.md, references/perf-go.md, references/perf-rust.md"
  savia.summary: "Auditoria estatica de rendimiento: detecta N+1 queries, async anti-patterns, memory allocation en loops, complejidad O(n2). Output: hallazgos priorizados por severidad + fix sugerido."
  savia.tags: "performance, hotspots, async, optimization"
  savia.trigger_keywords: "performance, hotspot, lento, optimiza, bottleneck, rendimiento"
---

# Performance Audit Intelligence

## Análisis estático — sin ejecución de código

Este skill analiza el código fuente para detectar funciones pesadas, anti-patrones de async y oportunidades de optimización. No ejecuta el código: mide complejidad, profundidad y patrones mediante análisis estático.

## Algoritmo de detección (4 fases)

### Fase 1 — Complejidad (40% peso)
Calcular por cada función/método:
- **Complejidad ciclomática**: if/else, switch/case, loops, ternarios, catch, operadores lógicos
- **Complejidad cognitiva**: anidamiento, breaks en flujo, recursión
- Umbrales: cyclomatic ≤10 OK, 11-20 HIGH, 21+ CRITICAL | cognitive ≤15 OK, 16-25 HIGH, 26+ CRITICAL

### Fase 2 — Async Anti-patterns (25% peso)
Cargar `references/perf-{lang}.md` del lenguaje detectado. Verificar:
- Blocking calls en contextos async
- Async void / floating promises / missing await
- Sync-over-async (Task.Result, .Wait(), .get())
- CPU-bound en event loops
- Goroutine/channel leaks (Go), mutex en async (Rust)

### Fase 3 — Hotspot Identification (20% peso)
Score compuesto por función: `(cyclomatic × 0.4) + (cognitive × 0.3) + (method_length × 0.15) + (nesting_depth × 0.1) + (fan_out × 0.05)`
Métricas adicionales:
- **Method length**: ≤30 OK, 31-60 MEDIUM, 61+ HIGH
- **Nesting depth**: ≤3 OK, 4-5 MEDIUM, 6+ HIGH
- **Fan-out** (dependencias llamadas): ≤7 OK, 8-12 MEDIUM, 13+ HIGH
- **Estimated O()**: detectar loops anidados → O(n²), O(n³), etc.

### Fase 4 — Test Coverage (15% peso)
Para cada hotspot identificado:
- Buscar ficheros de test que referencien la función/clase
- Verificar si existen tests unitarios, de integración o characterization
- Marcar como UNTESTED si no hay cobertura → eleva severidad +1 nivel

## Clasificación de severidad

| Severidad | Criterio | Impacto |
|-----------|----------|---------|
| CRITICAL | cyclomatic ≥21 O cognitive ≥26 O async blocking en hot path | Degradación medible en producción |
| HIGH | cyclomatic 11-20 O cognitive 16-25 O N+1 queries | Riesgo de latencia bajo carga |
| MEDIUM | method_length >60 O nesting >5 O fan-out >12 | Mantenibilidad reducida (solo --strict) |
| LOW | Best practice no seguida (solo --strict) | Oportunidad de mejora |

## Scoring

```
Performance Score = 100 - (Σ penalties)
Penalty: CRITICAL = -15, HIGH = -8, MEDIUM = -3, LOW = -1
Score mínimo = 0
```

Rangos: ≥80 GOOD, 60-79 NEEDS_WORK, 40-59 POOR, <40 CRITICAL

## IDs y referencias

Formato: `PA-{NNN}` (secuencial por auditoría).
Los IDs son estables entre `/perf-audit`, `/perf-fix` y `/perf-report`.
Los hallazgos con severidad ≥HIGH se registran automáticamente en `/debt-track`.

## Test-First Workflow (/perf-fix)

ANTES de optimizar cualquier función:
1. **Verificar tests existentes** — buscar test files que referencien la función
2. **Si no existen** → crear **characterization tests** (Golden Master):
   - Capturar inputs/outputs actuales de la función
   - Incluir edge cases detectados en análisis de complejidad
   - Cubrir ramas principales del flujo
3. **Ejecutar baseline** — todos los tests deben PASAR
4. **Aplicar optimización** — refactor, async fix, algoritmo mejorado
5. **Re-ejecutar tests** — si FAIL → revertir, si PASS → confirmar mejora

## Patrones de optimización disponibles

- **Refactor complejo**: extract method, simplify conditions, remove nesting
- **Async fix**: convertir blocking a async, Promise.all, parallel execution
- **N+1 fix**: eager loading, batch queries, DataLoader pattern
- **Memory**: pre-allocation, StringBuilder, generator/iterator, object pooling
- **Algorithm**: hash lookup vs linear search, sort optimization, caching

## Integración

| Feature | Relación |
|---------|----------|
| architecture-intelligence | Reusa detección de lenguaje |
| language packs | perf-{lang}.md complementa convenciones |
| /debt-track | Hallazgos PA-NNN → deuda técnica |
| /project-audit | /perf-audit es dimensión nueva del audit |
| test-runner hook | /perf-fix usa test runner para baseline |
| context-health | Output-first: >30 líneas → fichero |

## Output

Directorio: `output/performance/`
Formato nombre: `{proyecto}-audit-{YYYY-MM-DD}.md`
