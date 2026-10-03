---
layer: peripheral
name: agent-code-map
description: Usar cuando un agente necesita conocer la arquitectura del proyecto sin leer ficheros completos.
allowed-tools: [Bash, Read, Glob, Grep, Write, Edit]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: beta
  savia.category: sdd-framework
  savia.context: project
  savia.priority: high
  savia.summary: "Formato .acm que el agente redacta y carga por capas. refresh-agent-maps.sh refresca cabeceras por repo y emite JSON; hash y generacion son manuales."
  savia.tags: "acm, agent-maps, codemap, context, sdd, architecture"
  savia.user-invocable: True
---
# Agent Code Map — Mapas Estructurales Persistentes

Genera ficheros `.acm` (Agent Code Map) pre-calculados que los agentes cargan
al inicio de cada sesión. Elimina la exploración ciega de arquitectura.

## Cuándo usar

Inicio de pipeline SDD (leer `INDEX.acm` y cargar solo las capas necesarias),
post-sprint o tras `/project-update` (refrescar cabeceras), proyecto nuevo
(redactar los `.acm` iniciales) y verificación (repos sin checkout o sin `.acm`).

## Qué es ejecutable hoy

No existen comandos `/codemap:*`: la generación, la carga y la verificación de
frescura por hash son procedimiento del agente (leer código, escribir el `.acm`
con el formato de abajo). Lo único ejecutable es el refresco de cabeceras:

```bash
bash scripts/refresh-agent-maps.sh <slug>          # todos los repos de projects/<slug>_main/<slug>/repos/
bash scripts/refresh-agent-maps.sh <slug> <repo>   # un solo repo
```

- Lee `projects/<slug>_main/<slug>/repos/*` y `.agent-maps/repos/*.acm`; casa repo y `.acm`
  ignorando mayúsculas, `-` y `_` (`Api_Core` → `api-core.acm`).
- Reescribe solo la **primera línea `> `** (cabecera): `refreshed: AAAA-MM-DD`; repo con solo
  `.git` → `status: stale-no-checkout`. El cuerpo no se toca. Escritura atómica (segura en concurrencia).
- Actualiza `refreshed:` en `INDEX.acm` (también atómico). **No** calcula hash ni crea `.acm`: sin `.acm` → `missing-acm`.
- stdout: JSON válido `{"slug","ts","repos":[{"repo","status","acm","counts":{cs,vue,sql,tf,csproj,controllers},"last_commit"}]}`.
  `status` ∈ `refreshed | missing-acm | stale-no-checkout | missing-repo | error`.
- Exit: `0` ok · `1` falta `repos/` o `.agent-maps/repos/`, algún repo en `missing-repo` o `error` (.acm no escribible;
  no toca `INDEX.acm` ni imprime `OK`) · `2` slug o repo inválido (solo `[A-Za-z0-9._-]`, sin `..`).

Tests: `tests/test-agent-code-map.bats`.

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

Cálculo de hash (manual, lo hace el agente al redactar el `.acm`): `sha256` del contenido
de todos los ficheros fuente del scope. `refresh-agent-maps.sh` no lo recalcula; solo
marca `refreshed:` y `stale-no-checkout`.

## Sistema @include

Carga bajo demanda (`@include domain/entities.acm`): el agente lo resuelve leyendo
el fichero. Máximo 150 líneas por .acm; si crece, dividir en subdirectorios
(`domain/entities/user.acm`, `domain/entities/order.acm`, etc.).

## Integración en pipeline SDD

```
[0] CARGAR  — leer INDEX.acm y las capas del scope
[1] Análisis — business-analyst lee spec + mapas
[2] Arquitectura — architect planifica con contexto real
[3] Spec    — sdd-spec-writer genera spec ejecutable
[4] Impl    — {lang}-developer implementa con mapas cargados
[5] QA      — test-engineer valida cobertura
[post-SDD]  ACTUALIZAR — bash scripts/refresh-agent-maps.sh <slug> + revisar .acm afectados
```

## Gemelo humano: .hcm

Cada `.acm` tiene un gemelo narrativo `.hcm` en `.human-maps/` (skill
`human-code-map`). `.acm` responde *qué existe y dónde* para agentes;
`.hcm` responde *por qué existe y cómo pensarlo* para humanos. Si el
hash del `.acm` cambia, el `.hcm` debe marcarse stale (a mano: no hay automatismo).

## Motor opcional: CodeGraph MCP

Si el MCP `codegraph` está activo (ver `.claude/skills/codegraph/SKILL.md`),
el agente puede usar su índice para redactar los `.acm` por capa y
`codegraph status --json` para juzgar frescura. No hay proyección automática
índice → `.acm`: es trabajo del agente. Sin CodeGraph, grep + lectura dirigida.
Confidencialidad: `.codegraph/` debe estar gitignored. Prohibido en N4b
(ver `docs/rules/domain/codegraph-confidentiality.md`).

## Anti-patterns

- **NUNCA** generar .acm con datos de proyectos privados de cliente (→ N4)
- **NUNCA** commitear .acm con información sensible al repo público
- **NUNCA** crear .acm de más de 150 líneas — dividir siempre
- **NUNCA** usar .acm `roto` sin regenerar primero
