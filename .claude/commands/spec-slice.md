---
name: spec-slice
description: Analizar un spec y dividirlo en slices de implementación optimizados para contexto
argument-hint: "<spec-path> [--max-files 3] [--max-tokens 15000]"
allowed-tools: [Read, Write, Bash, Glob, Grep]
model_tier: mid
context_cost: medium
tier: core
---

# /spec-slice — Particionado de specs en slices ejecutables

## Prerrequisitos

- Spec aprobado (`.spec.md`) con: requisitos funcionales, ficheros target, criterios de aceptación
- Proyecto con código fuente existente (para estimar tamaños de fichero)

## Flujo

### 1. Cargar y analizar spec

```
Leer spec → Extraer:
  - Requisitos funcionales (RF-01, RF-02, ...)
  - Ficheros a crear/modificar
  - Dependencias entre requisitos
  - Criterios de aceptación
  - Stack tecnológico
```

### 2. Identificar componentes lógicos

Agrupar requisitos por capa y dominio:

| Capa | Ejemplos |
|------|----------|
| Domain | Entities, Value Objects, Domain Services |
| Application | Use Cases, Commands, Queries, DTOs |
| Infrastructure | Repositories, EF Configs, External Services |
| API | Controllers, Middleware, Filters |
| Tests | Unit, Integration, E2E |

### 3. Crear slices

Cada slice cumple TODAS estas restricciones:

- **≤3 ficheros** a crear/modificar (para caber en context prime)
- **≤1 grupo de reglas de negocio** (coherencia lógica)
- **≤15K tokens estimados** de context load (ficheros + spec excerpt)
- **Dependencias explícitas** (slice 2 depende de slice 1 si usa sus tipos)

Algoritmo de agrupación:

```
1. Ordenar requisitos por capa: Domain → Application → Infrastructure → API → Tests
2. Para cada capa:
   a. Agrupar ficheros relacionados (máx 3)
   b. Estimar tokens: sum(líneas_fichero × 1.3) + 2000 (overhead)
   c. Si > 15K tokens → subdividir
3. Detectar dependencias: si slice B importa tipos de slice A → B depends_on A
4. Calcular critical path (orden serial mínimo)
5. Identificar slices paralelizables (sin dependencias cruzadas)
```

### 4. Estimar tokens por slice

Fórmula de estimación:

```
tokens_slice = spec_excerpt(~2K)
             + sum(fichero_target × factor_lenguaje)
             + test_template(~500)
             + arch_context(~1K)

factor_lenguaje:
  C#/Java:       líneas × 1.4
  TypeScript/JS:  líneas × 1.2
  Python:         líneas × 1.1
  Go/Rust:        líneas × 1.3
```

### 5. Generar output

Guardar en `output/spec-slices/{spec-name}/`:

**`slices.yaml`** — Campos por slice: `id`, `title`, `requirements[]`, `files_create[]`, `files_modify[]`, `estimated_tokens`, `estimated_hours`, `depends_on[]`, `layer`. Campos globales: `spec_name`, `spec_path`, `stack`, `total_slices`, `estimated_tokens_total`, `estimated_hours_serial`, `estimated_hours_parallel`, `critical_path[]`, `parallel_groups[]`.

**`slice-{n}.md`** — Excerpt de spec con: título, requisitos incluidos, ficheros a crear/modificar, dependencias de otros slices, criterios de aceptación (subset del spec original).

### 6. Mostrar resumen

```
╔═══════════════════════════════════════════════════╗
║  🦉 Spec sliced: AB102-api-salas                 ║
╠═══════════════════════════════════════════════════╣
║  Slices: 5 · Tokens: ~58K · Horas: 12 (8 ∥)     ║
║  Critical path: 1 → 2 → 3 → 5                    ║
║  Parallelizable: Slices 3 y 4                     ║
║  Output: output/spec-slices/AB102-api-salas/      ║
╠═══════════════════════════════════════════════════╣
║  Siguiente: /dev-session start <spec-path>        ║
╚═══════════════════════════════════════════════════╝
```

## Parámetros opcionales

| Param | Default | Descripción |
|-------|---------|-------------|
| `--max-files` | 3 | Máx ficheros por slice |
| `--max-tokens` | 15000 | Máx tokens estimados por slice |
| `--format` | yaml | Output: yaml, json, markdown |

## Reglas

- Si el spec tiene <3 ficheros totales → un solo slice (no subdividir)
- Si un fichero supera 8K tokens solo → dedicar un slice entero a ese fichero
- Tests van en slices separados de la implementación (excepto TDD red phase)
- El orden de slices sigue la convención de capas del stack detectado
