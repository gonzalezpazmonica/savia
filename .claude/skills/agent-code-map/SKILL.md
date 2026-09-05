---
layer: peripheral
name: agent-code-map
description: Usar cuando un agente necesita conocer la arquitectura del proyecto sin leer ficheros completos.
allowed-tools: [Bash, Read, Glob, Grep, Write, Edit]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: sdd-framework
  savia.context: project
  savia.maturity: experimental
  savia.priority: high
  savia.summary: "Genera INDEX.acm + mapas por capa (domain, infra, api) desde el código fuente. Valida frescura por hash. Carga progresiva con @include. Integrado en SDD step [0]. Elimina 30–60% de exploración ciega al inicio de cada sesión de agente."
  savia.tags: "acm, agent-maps, codemap, context, sdd, architecture"
  savia.user-invocable: True
---
# Agent Code Map — Mapas Estructurales Persistentes

Genera ficheros `.acm` (Agent Code Map) pre-calculados que los agentes cargan
al inicio de cada sesión. Elimina la exploración ciega de arquitectura.

## Cuándo usar

- **Inicio de pipeline SDD** (`/codemap:load`): dar contexto de arquitectura al agente
- **Post-sprint** (`/codemap:refresh`): mantener mapas actualizados tras cambios
- **Nuevo proyecto** (`/codemap:generate`): generar mapas iniciales desde cero
- **Verificación** (`/codemap:check`): detectar mapas obsoletos o rotos

## Comandos slash

| Comando | Descripción |
|---------|-------------|
| `/codemap:generate [scope]` | Genera todos los .acm para el proyecto o scope |
| `/codemap:check` | Verifica frescura de todos los .acm (fresco/obsoleto/roto) |
| `/codemap:load <scope>` | Carga los .acm relevantes en el contexto del agente |
| `/codemap:refresh --incremental` | Regenera solo los .acm cuyo código fuente cambió |
| `/codemap:stats` | Muestra: total .acm, líneas, estado de frescura, cobertura |

## Formato .acm

Cada fichero `.acm` es Markdown con estructura fija:

```markdown
# [Capa] — [Descripción] (.acm)
> hash: sha256:[HASH_CODIGO_FUENTE] | generated: YYYY-MM-DD | lines: N

## [Entidad/Módulo]
- **Tipo**: Clase | Interface | Servicio | Repositorio | Controller
- **Fichero**: `src/ruta/al/fichero.ext:LINEA`
- **Propósito**: [descripción 1 línea]
- **Dependencias**: [lista de dependencias clave]
- **API pública**: [métodos/endpoints expuestos]

@include domain/entities.acm   ← carga bajo demanda
```

## INDEX.acm — Punto de entrada

```markdown
# INDEX — Agent Code Map (.acm)
> hash: [HASH] | generated: YYYY-MM-DD | project: [nombre]

## Navegación por capa

| Capa | Fichero | Elementos | Prioridad |
|------|---------|-----------|-----------|
| Domain Entities | domain/entities.acm | N entidades | 🔴 Alta |
| Domain Services | domain/services.acm | N servicios | 🔴 Alta |
| Infrastructure | infrastructure/repositories.acm | N repos | 🟡 Media |
| API | api/controllers.acm | N controllers | 🟡 Media |

## Cargar por scope

- Todo: `@include domain/entities.acm`, `@include domain/services.acm`, ...
- Solo dominio: `@include domain/entities.acm`, `@include domain/services.acm`
- Solo API: `@include api/controllers.acm`
```

## Estructura en disco

```
.agent-maps/
├── INDEX.acm              ← Siempre cargar primero
├── domain/
│   ├── entities.acm       ← Entidades de dominio
│   └── services.acm       ← Servicios de negocio
├── infrastructure/
│   └── repositories.acm   ← Repositorios y acceso a datos
└── api/
    └── controllers.acm    ← Controllers y endpoints
```

## Modelo de frescura

| Estado | Condición | Acción del agente |
|--------|-----------|------------------|
| `fresco` | Hash .acm coincide con código fuente | Usar directamente |
| `obsoleto` | Cambios internos, estructura intacta | Usar con aviso |
| `roto` | Ficheros eliminados o firmas públicas cambiadas | Regenerar antes de usar |

Cálculo de hash: `sha256` del contenido de todos los ficheros fuente del scope.

## Sistema @include

Los agentes cargan .acm bajo demanda para minimizar tokens:

```markdown
@include domain/entities.acm     ← Se resuelve en runtime
@include domain/services.acm     ← Solo si el agente lo necesita
```

Reglas: máximo 150 líneas por .acm. Si crece, dividir en subdirectorios:
`domain/entities/user.acm`, `domain/entities/order.acm`, etc.

## Integración en pipeline SDD

```
[0] CARGAR  — /codemap:check && /codemap:load <scope>
[1] Análisis — business-analyst lee spec + mapas
[2] Arquitectura — architect planifica con contexto real
[3] Spec    — sdd-spec-writer genera spec ejecutable
[4] Impl    — {lang}-developer implementa con mapas cargados
[5] QA      — test-engineer valida cobertura
[post-SDD]  ACTUALIZAR — /codemap:refresh --incremental
```

## Gemelo humano: .hcm

Cada `.acm` tiene un gemelo narrativo `.hcm` en `.human-maps/` (skill
`human-code-map`). `.acm` responde *qué existe y dónde* para agentes;
`.hcm` responde *por qué existe y cómo pensarlo* para humanos. Si el
hash del `.acm` cambia, el `.hcm` se marca automáticamente como stale.


## Motor opcional: CodeGraph MCP

Si el MCP `codegraph` está activo (ver `.claude/skills/codegraph/SKILL.md`),
`/codemap:generate` invoca `codegraph index` y proyecta el índice SQLite
a `.acm` por capa; `/codemap:check` lee `codegraph status --json` para
frescura. Sin CodeGraph, cae a grep + tree-sitter ad-hoc sin error.
Confidencialidad: `.codegraph/` debe estar gitignored. Prohibido en N4b
(ver `docs/rules/domain/codegraph-confidentiality.md`).

## Anti-patterns

- **NUNCA** generar .acm con datos de proyectos privados de cliente (→ N4)
- **NUNCA** commitear .acm con información sensible al repo público
- **NUNCA** crear .acm de más de 150 líneas — dividir siempre
- **NUNCA** usar .acm `roto` sin regenerar primero
