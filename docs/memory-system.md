# Sistema de Memoria — PM-Workspace

> Guía para aprovechar el sistema de memoria persistente del AI coding assistant (Claude Code / OpenCode) en pm-workspace.

---

## Jerarquía de Memoria

PM-Workspace usa la jerarquía completa de memoria de Claude Code / OpenCode:

| Tipo | Ubicación | Propósito | Compartido |
|---|---|---|---|
| **Proyecto (global)** | `~/claude/CLAUDE.md` | Rol PM, reglas críticas, estructura | Equipo (repo) |
| **Reglas modulares** | `docs/rules/domain/*.md` | Reglas bajo demanda por tema | Equipo (repo) |
| **Reglas por lenguaje** | `docs/rules/languages/*.md` | Convenciones con auto-carga por `paths:` | Equipo (repo) |
| **Proyecto local** | `~/claude/CLAUDE.local.md` | Config privada: PATs, proyectos reales | Solo tú |
| **Proyecto específico** | `projects/{nombre}/CLAUDE.md` | Config por proyecto Azure DevOps | Equipo (repo) |
| **Auto Memory** | `~/.claude/projects/*/memory/` | Notas automáticas de Claude por proyecto | Solo tú |
| **Usuario** | `~/.claude/CLAUDE.md` | Preferencias personales globales | Solo tú |
| **User rules** | `~/.claude/rules/*.md` | Preferencias modulares personales | Solo tú |

---

## Path-Specific Rules (auto-carga por tipo de fichero)

Las reglas de lenguaje incluyen frontmatter YAML `paths:` que activa la carga automática cuando Claude trabaja con ficheros del lenguaje correspondiente:

```yaml
---
paths:
  - "**/*.cs"
  - "**/*.csproj"
---
# Regla: Convenciones .NET
```

**Beneficio**: No necesitas cargar manualmente con `@` las convenciones del lenguaje. Se activan solas al tocar un `.cs`, `.py`, `.go`, etc.

### Lenguajes con auto-carga

| Lenguaje | Extensiones |
|---|---|
| C#/.NET | `.cs`, `.csproj`, `.sln`, `.razor` |
| TypeScript | `.ts`, `.mts`, `.cts` |
| Angular | `.component.ts`, `.module.ts`, `.service.ts` |
| React | `.tsx`, `.jsx` |
| Java | `.java`, `pom.xml`, `build.gradle` |
| Python | `.py`, `pyproject.toml`, `requirements.txt` |
| Go | `.go`, `go.mod` |
| Rust | `.rs`, `Cargo.toml` |
| PHP | `.php`, `composer.json` |
| Swift | `.swift`, `Package.swift` |
| Kotlin | `.kt`, `.kts`, `build.gradle.kts` |
| Ruby | `.rb`, `Gemfile` |
| VB.NET | `.vb`, `.vbproj` |
| COBOL | `.cob`, `.cbl`, `.cpy` |
| Flutter | `.dart`, `pubspec.yaml` |
| Terraform | `.tf`, `.tfvars`, `.hcl` |

### Reglas de dominio con auto-carga

| Regla | Extensiones |
|---|---|
| Infrastructure as Code | `.tf`, `.tfvars`, `.bicep`, `Dockerfile`, `docker-compose*.yml` |
| GitHub Flow | `.github/**`, `.gitignore`, `.gitattributes` |
| Azure Repos | `azure-pipelines*.yml`, `.azuredevops/**` |

---

## Auto Memory

Savia guarda memoria canónica en `~/.savia-memory/auto/MEMORY.md` (índice Tier A).
Estructura:

```
~/.savia-memory/
├── auto/
│   └── MEMORY.md              ← Índice canónico (≤200 líneas, ≤25KB)
├── sessions/YYYY-MM-DD/       ← Snapshots de sesión
├── projects/                  ← Memoria por proyecto
└── jsonl-archive/             ← Archivos JSONL históricos
```

**MEMORY.md hard-cap: 200 líneas / 25 KB.** Entradas < 150 chars.
El índice se actualiza automáticamente con `memory-store.sh save` y se
puede regenerar con `memory-index-rebuild.sh`.

La estructura legacy `~/.claude/projects/<project>/memory/` sigue siendo
escaneada como fuente secundaria durante la migración.

### 2-tier rotation (SE-073)

Cada memory file lleva en frontmatter:

```yaml
access_count: 0    # incrementado por scripts/memory-access.sh al consumir
last_access: YYYY-MM-DD
pin: true          # opcional — fuerza Tier A independientemente del score
```

Score de promoción: `access_count + recency_bonus(<30d=+3) + pin_bonus(true=+999) + identity_bonus(user_*=+500)`.

**Comandos**:
- `bash scripts/memory-tier-rotate.sh --status`  — muestra distribución actual
- `bash scripts/memory-tier-rotate.sh --dry-run` — preview sin escribir
- `bash scripts/memory-tier-rotate.sh`           — ejecuta rotación (escribe MEMORY.md y MEMORY-ARCHIVE.md)
- `bash scripts/memory-access.sh <basename>`     — incrementa contador al cargar una entry

**Garantías**:
- `user_*` files siempre van a Tier A (foundational identity)
- `pin: true` files siempre van a Tier A
- Empate por score → ordena por mtime descendente (recientes primero)

### Pedir a Claude que recuerde algo

```
> Recuerda que en este proyecto usamos pnpm, no npm
> Guarda en memoria que los tests de integración necesitan Redis local
> Anota que el equipo prefiere commits en español
```

### Sincronizar memoria con `/memory-sync`

El comando `/memory-sync` consolida insights del sprint actual en los topic files de auto memory.

---

## Agent Memory — 3 Niveles

Los agentes tienen memoria persistente separada en 3 niveles por privacidad y portabilidad:

| Nivel | Ruta | En git | Contenido |
|---|---|---|---|
| **Publica** | `public-agent-memory/{agente}/` | SI | Best practices genericas (DDD, SOLID, security) |
| **Privada** | `private-agent-memory/{agente}/` | NO | Contexto personal, equipo, organización |
| **Proyecto** | `projects/{p}/agent-memory/{agente}/` | NO | Datos del cliente, estado de procesamiento |

**Orden de carga**: publica → privada → proyecto. Proyecto prevalece en conflictos.

**Regla canonica**: `docs/rules/domain/agent-memory-isolation.md`

---

## Imports con `@`

CLAUDE.md soporta imports con sintaxis `@ruta/al/fichero`:

```markdown
Config detallada: @docs/rules/domain/pm-config.md
Buenas prácticas: @docs/best-practices-claude-code.md
```

Las rutas son relativas al fichero que contiene el import. Los imports se resuelven recursivamente (máx. 5 niveles).

---

## Symlinks para Reglas Compartidas

Si trabajas en proyectos fuera de `~/claude/`, puedes compartir las reglas de lenguaje via symlinks:

```bash
# En el proyecto externo, crear symlink a los language packs
ln -s ~/claude/docs/rules/languages/ /ruta/proyecto/.claude/rules/languages

# O solo un lenguaje específico
ln -s ~/claude/docs/rules/languages/python-conventions.md /ruta/proyecto/.claude/rules/python.md
```

---

## `--add-dir` para Proyectos Externos

Para trabajar en un proyecto externo manteniendo acceso a las reglas del workspace:

```bash
# Cargar reglas de pm-workspace mientras trabajas en otro repo
CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1 claude --add-dir ~/claude
```

---

## User-Level Rules (`~/.claude/rules/`)

Preferencias personales que aplican en TODOS tus proyectos (no solo pm-workspace):

```
~/.claude/rules/
├── pm-preferences.md     ← Estilo de comunicación del PM
├── report-format.md      ← Formato preferido de reportes
└── git-workflow.md       ← Preferencias de Git personales
```

Estas reglas tienen menor prioridad que las del proyecto.

---

## Memory Store Enhancements (v1.9.0)

### Concepts Dimension

Entries now support a `--concepts` parameter (CSV) stored as JSON array. This enables 2D taxonomy: type (decisión, bug, pattern...) + concepts (testing, ci, architecture...). Search and stats both leverage concepts for better categorization.

### Progressive Disclosure (3 layers)

`/memory-recall` offers three levels to minimize token consumption: `index` (titles + types only), `timeline` (last N with summaries), `detail` (full content of a specific entry by topic_key).

### Token Economics

Every saved entry includes `tokens_est` (content length / 4). `/memory-stats` shows total tokens in store, breakdown by type and concept, and recommends pruning when thresholds are exceeded.

### Auto-Capture

The `memory-auto-capture.sh` PostToolUse hook automatically captures patterns from Edit/Write operations on key files (scripts, rules, commands). Rate-limited to 1 capture per 5 minutes.

### NL→Command Resolution

`/nl-query` uses `intent-catalog.md` (60+ patterns, bilingual) to map natural language to commands. Confidence scoring: base (70-95%) + context bonus (+0-5%) + history bonus (+0-3%). Thresholds: ≥80% auto-execute, 50-79% confirm, <50% suggest top 3.

### Trust-Gated Memory (SE-352)

Cada entrada lleva una clase de origen (`origin`) que gobierna su confianza para
la consolidación. Cuatro clases:

- `owner` — escrita por la operadora (o vía `--source user:explicit`)
- `agent` — escrita por un agente sobre hechos verificados localmente (`tool:*`, `file:*`, `verified:*`)
- `untrusted` — origen de red, subagente no verificado, o entrada sin `src:` (fail-safe)
- `system` — generada por hooks/scripts de infraestructura (sin semántica de decisión)

Reglas:
- **Fail-safe**: una entrada sin `--origin` ni source confiable se clasifica `untrusted`. NUNCA `owner` por defecto.
- **Taint de turno**: tras una tool de red (webfetch, curl, git fetch...), las siguientes entradas del turno se degradan a `untrusted` (hook `memory-origin-gate.sh`). El guardado identifica la sesión con `CLAUDE_CODE_SESSION_ID` (o `SESSION_ID`); sin identificador y con una marca vigente, degrada igualmente (fallo cerrado).
- **Consolidación**: `memory-store.sh consolidate` excluye `untrusted`/`system` de la promoción (`--dry-run` para previsualizar). Excluir no es borrar: las entradas excluidas, y las antiguas sin campo `origin`, pasan a `output/.memory-store-quarantine.jsonl` y siguen recuperables. Una entrada recuperada nunca promueve su propio nivel de confianza.
- **Filtro de búsqueda**: `memory-store.sh search "..." --min-origin owner|agent|untrusted`.
- **Auditoría**: `memory-store.sh audit-origins` reporta la distribución de orígenes.

Integridad: `save` serializa con `json.dumps`, trabaja bajo cerrojo (`<almacén>.lock`) y escribe de forma atómica; si el dato no puede quedar íntegro y recuperable, sale con error y no escribe nada. `--type` solo admite letras, números, `-` y `_`.

Persistencia: el campo `origin` se guarda en el JSONL y en el índice `MEMORY.md` como sufijo `· src:{origin}`.

---

## Activar búsqueda semántica (SE-143)

El sistema soporta tres levels de búsqueda:

| Level | Modo | Requisito |
|---|---|---|
| 0 | grep puro | ninguno |
| 1 | embeddings sin backend | `sentence-transformers` |
| 2 | vector + híbrido (recomendado) | `sentence-transformers` + `faiss-cpu` |

**Instalar deps:**
```bash
bash scripts/install-memory-deps.sh
```

El instalador crea `~/.savia/venv`, instala Torch CPU-only y no modifica el
Python del sistema. `hnswlib` sigue soportado por el motor, pero no forma parte
de la instalación estándar porque puede requerir compilador.

**Verificar estado:**
```bash
bash scripts/memory-store.sh doctor
```

Si `doctor` muestra `Level: 0`, la búsqueda semántica está desactivada.
Instalar las deps y ejecutar `memory-store.sh rebuild-index` para activarla.

---

## Best Practices

1. **MEMORY.md conciso** — max 200 lineas AND 25KB. Each entry < 150 chars. Mover detalles a topic files
2. **Topic files enfocados** — un tema por fichero (debugging, architecture, etc.)
3. **Revisar periódicamente** — actualizar memoria al cambiar de sprint
4. **No duplicar** — si algo ya está en CLAUDE.md del proyecto, no repetirlo en auto memory
5. **`paths:` solo donde aplica** — no añadir frontmatter a reglas de dominio genéricas
6. **Concepts tags** — usar `--concepts` al guardar para facilitar búsquedas por dominio
7. **Consolidar sesiones** — ejecutar `/memory-consolidate` al final de sesiones largas
