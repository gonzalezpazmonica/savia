---
layer: peripheral
name: context-optimized-dev
description: Usar cuando se desarrolla con presupuesto de contexto limitado.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: sdd-framework
  savia.maturity: stable
  savia.maturity: beta
  savia.priority: high
  savia.summary: "Desarrollo optimizado para contexto limitado: dev-session protocol con slices, subagentes aislados y persistencia en disco. Maximiza calidad de codigo con 40% de ventana libre."
  savia.tags: "context, optimization, dev-session, slicing"
---

# Context-Optimized Development — Skill

> Guía operativa para producir código de alta calidad con ~40% de context window libre.

## Modelo mental

```
Context window (200K tokens)
├── Auto-loaded (rules, CLAUDE.md): ~120K (60%) — NO controlable
├── Conversación acumulada: variable
└── Espacio libre para trabajo: ~80K (40%) — ESTE es tu presupuesto
```

**Regla de oro**: Si tu próxima acción va a consumir >15K tokens → delégala a un subagent.

## Patrones de delegación a subagents

### Qué incluir en el prompt del subagent

| Elemento | Tokens típicos | Cuándo incluir |
|----------|---------------|----------------|
| Spec-slice excerpt | 1.5-2K | SIEMPRE — es la fuente de verdad |
| Ficheros target (actuales) | 1-8K por fichero | SIEMPRE — el agente necesita el código actual |
| Test expectations | 0.5-1K | Si hay tests que deben pasar |
| Convención de arquitectura | 0.5-1K | 1 párrafo, no toda la regla |
| Ejemplo similar del proyecto | 1-3K | Si existe un patrón a seguir |

### Qué NO incluir

- El spec completo (solo el excerpt del slice)
- CLAUDE.md del proyecto (el agente ya tiene las reglas cargadas)
- Ficheros no relacionados con el slice
- Histórico de slices anteriores (está en disco)
- Skills completas (solo la sección relevante)

### Template de invocación

```
Subagent: {lang}-developer
Input:
  1. [Spec slice]: {contenido del slice-{n}.md}
  2. [Ficheros actuales]: {solo los listados en el slice}
  3. [Tests esperados]: {qué assertions deben pasar}
  4. [Convención]: {1 párrafo de arquitectura aplicable}
Output esperado:
  - Ficheros modificados/creados (código completo)
  - Notas de implementación (decisiones tomadas, trade-offs)
  - Ficheros de test si aplica
```

## Templates de context priming por tipo de tarea

### Implementar un handler/controller

```
Cargar: spec-slice + interface del servicio + DTO + test template
NO cargar: repositorio (el handler no lo toca directamente)
Tokens estimados: 2K + 2K + 1K + 1K = 6K
```

### Implementar un repositorio

```
Cargar: spec-slice + entidad domain + interface repo + EF DbContext (solo el DbSet)
NO cargar: controllers, otros repos, migrations
Tokens estimados: 2K + 2K + 1K + 1K = 6K
```

### Escribir tests unitarios

```
Cargar: spec-slice + código a testear + test fixture base (si existe)
NO cargar: implementaciones de dependencias (usar mocks)
Tokens estimados: 2K + 4K + 1K = 7K
```

### Migration/configuración EF

```
Cargar: spec-slice + entidad + configuraciones existentes similares
NO cargar: todo el DbContext, otros entities
Tokens estimados: 2K + 2K + 2K = 6K
```

### Frontend component

```
Cargar: spec-slice + componente padre + design system tokens + API contract
NO cargar: otros componentes, store completo, router
Tokens estimados: 2K + 3K + 1K + 1K = 7K
```

## Fórmulas de estimación de tokens

### Por tipo de fichero

| Tipo | Factor (tokens/línea) | Ejemplo 100 líneas |
|------|----------------------|-------------------|
| C# / Java | 1.4 | ~140 tokens |
| TypeScript / JavaScript | 1.2 | ~120 tokens |
| Python | 1.1 | ~110 tokens |
| Go / Rust | 1.3 | ~130 tokens |
| YAML / JSON config | 0.8 | ~80 tokens |
| Markdown (spec) | 1.0 | ~100 tokens |

### Budget por fase (slice típico)

| Fase | Budget | Uso típico |
|------|--------|------------|
| Context Prime | 15K | Spec (2K) + Source (8K) + Tests (3K) + Arch (2K) |
| Implement | 12K subagent | Prompt (3K) + Files (6K) + Output (3K) |
| Validate | 8K × 2 subagents | Test run (4K) + Coherence check (4K) |
| Review | 12K subagent | Full diff (6K) + Review output (6K) |

## Anti-patrones

| # | Anti-patrón | Síntoma | Solución |
|---|------------|---------|----------|
| 1 | Cargar proyecto entero | `@src/` en prompt (50-200K tokens) | Usar `/spec-slice` para ficheros exactos |
| 2 | Múltiples slices sin compact | Contexto >60K, respuestas degradadas | `/compact` obligatorio entre slices |
| 3 | Recursión de agentes sin reducción | Agente invoca otro con todo su contexto | Mínimo necesario por tarea |
| 4 | Pasar spec completo al agente | 5K tokens cuando solo necesita 2K del slice | Solo `slice-{n}.md` |
| 5 | No persistir estado | Progreso perdido tras `/compact` | `state.json` después de cada fase |
## Métricas de eficiencia
| Métrica | Objetivo | Cómo medir |
|---------|----------|------------|
| Tokens por slice | <15K main + 12K subagent | Monitorizar en `/dev-session status` |
| Rework rate | <15% | Slices que requieren >1 intento en Fase 4 |
| Coherence score | ≥95% | Output de coherence-validator |
| Context exhaustion | 0 incidents | Sesiones que agotan contexto |
## Referencias
- `dev-session-protocol.md` — Protocolo de 5 fases
- `context-health.md` — Reglas de salud de contexto
- `agent-context-budget.md` — Budgets por categoría de agente
- `spec-driven-development/SKILL.md` — Flujo SDD completo
