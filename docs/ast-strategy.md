# Estrategia AST de Savia — Comprensión y Calidad de Código

> Documento técnico: cómo Savia usa Abstract Syntax Trees para entender código legado
> y garantizar la calidad del código generado por sus agentes.

---

## El problema que resuelve

Los agentes de IA generan código con alta velocidad. Sin validación estructural, ese código puede:
- Introducir patrones async bloqueantes que crashean en producción
- Crear consultas N+1 que degradan el rendimiento al 10% bajo carga real
- Silenciar excepciones en `catch {}` vacíos que ocultan fallos críticos
- Modificar un fichero de 300 líneas sin entender sus dependencias internas

Savia resuelve ambos problemas con la misma tecnología: AST.

---

## Arquitectura cuádruple: cuatro propósitos, un árbol

```
Código fuente
     │
     ▼
Árbol de Sintaxis Abstracta (AST)
     │
     ├──► Comprensión (ANTES de editar)          ← Hook PreToolUse
     │         Entiende lo que ya existe
     │         No modifica nada
     │         Pre-edit context injection
     │
     ├──► Calidad (DESPUÉS de generar)            ← Hook PostToolUse async
     │         Valida lo que se acaba de escribir
     │         12 Quality Gates universales
     │         Informe con score 0-100
     │
     ├──► Mapas de código (.acm)                  ← Contexto persistente entre sesiones
     │         Pre-generados antes de la sesión
     │         150 líneas máx. por fichero .acm
     │         Carga progresiva con @include
     │
     └──► Mapas humanos (.hcm)                    ← Lucha activa contra deuda cognitiva
               Narrativa en lenguaje natural
               Validados por humanos, no por CI
               Por qué existe el código, no solo qué hace
```

La clave del diseño: el mismo árbol sirve para cuatro fases del ciclo de vida del código,
con herramientas distintas y en momentos distintos del pipeline de hooks.

---

## Parte 1 — Comprensión de código legado

### El principio

Antes de que un agente edite un fichero, Savia extrae su mapa estructural.
El agente recibe ese mapa en su contexto, como si hubiera leído el código de antemano.

### Pipeline de extracción (3 capas)

```
Fichero objetivo
      │
      ▼
Capa 1: Tree-sitter (universal, 0 dependencias de runtime)
  • Todos los lenguajes del Language Pack
  • Clases, funciones, métodos, enums
  • Import declarations
  • ~1-3s, 95% cobertura semántica

      │ (si no disponible)
      ▼
Capa 2: Herramienta nativa semántica del lenguaje
  • Python: ast.walk() (módulo built-in, 100% precisión)
  • TypeScript: ts-morph (Compiler API completa)
  • Go: gopls symbols
  • C#: Roslyn SyntaxWalker
  • Rust: cargo check + rustfmt AST
  • Java: javap -c, semgrep
  • ~2-10s, 100% cobertura semántica

      │ (si no disponible)
      ▼
Capa 3: Grep-structural (0 dependencias absolutas)
  • Regex universal para los 16 lenguajes
  • Extrae clases, funciones, imports por patrones
  • <500ms, ~70% cobertura semántica
  • Siempre disponible — nunca falla
```

**Regla de degradación garantizada**: si todas las herramientas avanzadas fallan,
grep-structural siempre funciona. Nunca se bloquea una edición por falta de herramienta.

### Trigger automático: PreToolUse hook

```
Usuario pide editar fichero
         │
         ▼
Hook: ast-comprehend-hook.sh (PreToolUse, matcher: Edit)
  • Lee file_path del input JSON del hook
  • Verifica: ¿fichero tiene ≥50 líneas?
  • Si sí: ejecuta ast-comprehend.sh --surface-only (timeout 15s)
  • Extrae: clases, funciones, complejidad ciclomática
  • Si complejidad > 15: emite advertencia visible
         │
         ▼
Agente recibe en su contexto:
  ╔══════════════════════════════════════════════════╗
  ║  AST Comprehension — Pre-edit context           ║
  ╚══════════════════════════════════════════════════╝
  Fichero: src/Services/AuthService.cs
  Líneas:  248  |  Clases: 1  |  Funciones: 12
  Complejidad: 42 puntos de decisión  WARN  Proceder con cautela

  Mapa estructural:
  { "classes": [{ "name": "AuthService", "line": 12 }],
    "functions": [{ "name": "ValidateToken", "line": 45 },
                  { "name": "RefreshSession", "line": 120 }] }
         │
         ▼
Agente edita con contexto completo del fichero
```

El hook es **non-async** porque debe completarse ANTES de que el agente edite.
El hook siempre hace `exit 0` — la comprensión es advisory, nunca bloquea.

### Output: Comprehension Report

Formato JSON unificado para todos los lenguajes:

```json
{
  "meta": {
    "file": "src/Services/AuthService.cs",
    "language": "csharp",
    "lines": 248,
    "tool": "roslyn"
  },
  "structure": {
    "classes": [{ "name": "AuthService", "line": 12, "methods": [...] }],
    "functions": [{ "name": "ParseJwt", "line": 300 }],
    "enums": [{ "name": "TokenStatus", "line": 400 }]
  },
  "imports": {
    "external": ["Microsoft.IdentityModel.Tokens"],
    "standard": ["System.Threading.Tasks"]
  },
  "complexity": {
    "total_decision_points": 42,
    "hotspots": [{ "name": "RefreshSession", "complexity": 14, "warn": true }]
  },
  "api_surface": { "public": ["ValidateToken", "RefreshSession"] },
  "summary": "Servicio JWT. 1 clase, 12 métodos. Hotspot: RefreshSession (CC=14)."
}
```

### Uso en modo legado (`--legacy-mode`)

Para proyectos heredados, el comando directo mapea todo sin umbrales:

```bash
# Mapear directorio completo de proyecto legado
bash scripts/ast-comprehend.sh src/Legacy/ --legacy-mode --output output/legacy-map.json

# Fichero específico con informe completo
bash scripts/ast-comprehend.sh src/OldModule.cs --output output/old-module-map.json
```

El script nunca aplica el umbral de 50 líneas (era del hook) y siempre emite `hotspots[0].warn`;
`--legacy-mode` se acepta por compatibilidad pero hoy no cambia la salida.
El objetivo es documentar todo, sin filtros.

> Calibración SE-376 (2026-10-03): el hook actual (`.claude/hooks/ast-comprehend-hook.sh`) filtra
> `Grep|Glob`, pero está registrado con matcher `Edit`; el flujo pre-edición descrito arriba no se
> ejecuta hoy.

---

## Parte 2 — Calidad del código generado

### Los 12 Quality Gates universales

Cada gate aplica a todos los lenguajes. La implementación varía; el criterio no.

| Gate | Nombre | Clasificación | Lenguajes |
|------|--------|---------------|-----------|
| QG-01 | Async/concurrencia bloqueante | BLOCKER | .NET, TypeScript, Python, Rust |
| QG-02 | Queries N+1 | ERROR | .NET, Java, Python, Ruby |
| QG-03 | Null dereference sin guard | BLOCKER | .NET, Go, Java, Swift/Kotlin |
| QG-04 | Magic numbers sin constante | WARNING | Todos los lenguajes |
| QG-05 | Empty catch / catch vacío | BLOCKER | .NET, Java, TypeScript, Go |
| QG-06 | Complejidad ciclomática >15 | WARNING | Todos los lenguajes |
| QG-07 | Métodos >50 líneas | INFO | Todos los lenguajes |
| QG-08 | Duplicación >15% | WARNING | Todos los lenguajes |
| QG-09 | Secrets hardcodeados | BLOCKER | Todos los lenguajes |
| QG-10 | Logging excesivo en producción | INFO | Todos los lenguajes |
| QG-11 | Código muerto / dead code | INFO | Todos los lenguajes |
| QG-12 | Lógica de negocio sin tests | BLOCKER | Todos los lenguajes |

**Gates bloqueantes** (QG-01, QG-03, QG-05, QG-09, QG-12): el score baja 10 puntos por instancia.
**Gates de error** (QG-02): 10 puntos por instancia.
**Gates de advertencia** (QG-04, QG-06, QG-08): 3 puntos por instancia.
**Gates informativos** (QG-07, QG-10, QG-11): 1 punto por instancia.

```
score = 100 - (BLOCKER × 10) - (WARNING × 3) - (INFO × 1)
```

### Arquitectura de validación (3 capas)

```
Código generado
      │
      ▼
Capa 1: Linter nativo del lenguaje
  • ESLint (TypeScript/JavaScript) → JSON
  • Ruff (Python) → JSON
  • golangci-lint (Go) → JSON
  • cargo clippy (Rust) → JSON
  • php-cs-fixer + phpstan (PHP) → JSON
  • RuboCop (Ruby) → JSON
  • Rápido, integrado, zero-config

      │ (en paralelo o como segunda capa)
      ▼
Capa 2: Semgrep (análisis semántico universal)
  • Un fichero YAML cubre 8+ lenguajes
  • 20 reglas custom para los 12 Quality Gates
  • Detecta: async bloqueante, N+1, null unsafe, empty catch, secrets
  • Portable entre proyectos y lenguajes

      │ (para .NET, TypeScript con LSP disponible)
      ▼
Capa 3: LSP / herramienta nativa semántica
  • C#: Roslyn, OmniSharp
  • TypeScript: tsserver (type checking profundo)
  • Go: gopls
  • Más preciso, más lento, para issues complejos
```

### Trigger automático: PostToolUse async hook

```
Agente escribe/edita fichero
         │
         ▼
Hook: ast-quality-gate-hook.sh (PostToolUse, async, matcher: Edit|Write)
  • Ejecuta en background — no bloquea al agente
  • Detecta lenguaje por extensión
  • Ejecuta ast-quality-gate.sh con el fichero
  • Normaliza output al Unified JSON Schema
  • Calcula score (0-100) y grade (A-F)
  • Si score < 60 (grade D o F): emite alerta visible
  • Guarda informe en output/ast-quality/
```

El hook es **async** porque corre después de la escritura y no debe bloquear el flujo.
El timeout es 60s para dar tiempo a herramientas lentas (Roslyn, TypeScript LSP).

### Unified JSON Schema

Todos los outputs normalizan al mismo contrato:

```json
{
  "meta": {
    "file": "src/Services/OrderService.cs",
    "language": "csharp",
    "tool_chain": ["dotnet-build", "semgrep"],
    "timestamp": "2026-03-29T10:00:00Z"
  },
  "score": 73,
  "grade": "C",
  "verdict": "ADVISORY",
  "issues": [
    {
      "gate": "QG-01",
      "name": "Async bloqueante",
      "severity": "BLOCKER",
      "file": "src/Services/OrderService.cs",
      "line": 47,
      "message": "Task.Result puede causar deadlock en ASP.NET context",
      "fix": "Usar await order.GetAsync() en lugar de .Result"
    }
  ],
  "summary": {
    "total_issues": 3,
    "blockers": 1,
    "warnings": 2,
    "infos": 0
  }
}
```

---

## Integración en el ciclo de vida del agente

```
Ciclo de desarrollo de una feature:

[1] EXPLORAR — /comprehension-report src/Module/
    └─► Mapa completo del módulo antes de tocar nada
    └─► Identifica hotspots, dependencias, API surface

[2] PLANIFICAR — Agente recibe spec + mapa estructural
    └─► Planificación informada sobre el código real

[3] IMPLEMENTAR — Agente edita ficheros
    └─► PreToolUse: ast-comprehend-hook.sh
        ├─► Mapa estructural inyectado en contexto
        └─► Advertencia automática si complejidad >15

[4] VALIDAR — Inmediatamente después de cada escritura
    └─► PostToolUse: ast-quality-gate-hook.sh (async)
        ├─► 12 Quality Gates ejecutados
        ├─► Score calculado
        └─► Alerta si grade < B (score < 80)

[5] REVISAR — code-reviewer evalúa PRs
    └─► Lee informes de ast-quality en output/ast-quality/
    └─► Incluye hallazgos en code review E1
```

---

## Soporte por Language Pack

| Language Pack | Comprensión | Quality Gate | Herramienta principal |
|---|---|---|---|
| C#/.NET | Roslyn SyntaxWalker | dotnet build + Semgrep | Roslyn |
| TypeScript | ts-morph | ESLint + tsserver | ts-morph |
| Angular/React | ts-morph | ESLint + Semgrep | ts-morph |
| Java/Spring | javap + semgrep | checkstyle + Semgrep | Semgrep |
| Python | ast.walk() built-in | Ruff + Semgrep | ast module |
| Go | gopls symbols | golangci-lint | gopls |
| Rust | cargo check | cargo clippy | Clippy |
| PHP/Laravel | php-parser | php-cs-fixer + phpstan | PHPStan |
| Ruby/Rails | RuboCop AST | RuboCop | RuboCop |
| Swift/iOS | sourcekitten | swiftlint | SwiftLint |
| Kotlin/Android | detekt | detekt | Detekt |
| Flutter/Dart | dart analyze | dart analyze | Dart SDK |
| Terraform/IaC | tflint | tflint + checkov | Checkov |
| COBOL | grep-structural | grep-structural | Grep |
| VB.NET | Roslyn SyntaxWalker | dotnet build + Semgrep | Roslyn |
| Go (módulos) | gopls | golangci-lint | gopls |

**Fallback universal**: grep-structural cubre los 16 lenguajes cuando la herramienta
primaria no está disponible. Los agentes nunca se quedan sin información estructural.

---

## Parte 3 — Mapas de código para agentes (.acm)

### Motor opcional: CodeGraph (MCP)

Los `.acm` se generan por defecto con grep + tree-sitter ad-hoc. Si el proyecto
activa el MCP [CodeGraph](https://github.com/colbymchenry/codegraph)
(`@colbymchenry/codegraph`, MIT), `agent-code-map` y `ast-comprehension`
usan su índice SQLite como backend — resuelve callers/callees/impact
semánticamente, no por matches de grep. Opt-in por proyecto:

```bash
npm i -g @colbymchenry/codegraph
cd <proyecto>
codegraph init -i
# Activar en opencode.json: mcp.codegraph.enabled = true
```

Confidencialidad: `.codegraph/` debe estar en `.gitignore` antes del primer
`codegraph init`. Prohibido en scope N4b (PM-Only). Ver
`docs/rules/domain/codegraph-confidentiality.md` y
`.opencode/skills/codegraph/SKILL.md`.


### El problema

Cada sesión de agente comienza desde cero. Sin contexto pre-generado, el agente
consume entre el 30 % y el 60 % de su ventana de contexto explorando la arquitectura
antes de escribir una sola línea de código.

Los Agent Code Maps (.acm) son mapas estructurales persistentes entre sesiones,
almacenados en `.agent-maps/` y optimizados para consumo directo por agentes.

### Estructura en disco

```
.agent-maps/
├── INDEX.acm              ← Punto de entrada raíz
├── domain/
│   ├── entities.acm       ← Entidades del dominio
│   └── services.acm       ← Servicios de negocio
├── infrastructure/
│   └── repositories.acm   ← Repositorios y acceso a datos
└── api/
    └── controllers.acm    ← Controllers y endpoints
```

### INDEX.acm — tabla de navegación raíz

```markdown
---
acm-version: "1.0"
scope: "project-root"
generated: "2026-03-29T10:00:00Z"
stack: "C#/.NET 8 + Azure"
---

| Capa | Fichero .acm | Elementos | Prioridad |
|------|-------------|-----------|-----------|
| Domain | domain/entities.acm | 18 entidades | FAIL Crítico |
| Application | domain/services.acm | 12 servicios | FAIL Crítico |
| Infrastructure | infrastructure/repositories.acm | 8 repos | WARN Alto |
| API | api/controllers.acm | 24 endpoints | OK Normal |

@include domain/entities.acm
@include domain/services.acm
```

### Frontmatter YAML de un .acm

```yaml
---
acm-version: "1.0"
scope: "domain/entities"
generated: "2026-03-29T10:00:00Z"
source-hash: "sha256:a3f2c1..."
includes:
  - infrastructure/repositories.acm
depends-on:
  - src/Domain/Entities/
---
```

**Límite de 150 líneas por .acm**: si crece, se parte en subdirectorios automáticamente.
**Sistema @include**: carga progresiva bajo demanda — el agente carga solo lo que necesita.

### Modelo de frescura

| Estado | Condición | Acción del agente |
|--------|-----------|-------------------|
| `fresh` | Hash del .acm coincide con el código fuente | Usar directamente |
| `stale` | Cambios internos pero estructura intacta | Usar con aviso |
| `broken` | Ficheros eliminados o firmas públicas cambiadas | Regenerar antes de usar |

### Integración en el pipeline SDD

Los .acm se cargan ANTES de `/spec:generate`. El agente conoce la arquitectura real
del proyecto desde el primer token, sin exploración ciega.

```
[0] CARGA — /codemap:check && /codemap:load <scope>
    └─► Agente recibe mapa pre-generado de la capa relevante
    └─► Tokens de contexto: exploración → razonamiento puro

[1-5] Pipeline SDD sin cambios
    └─► PreToolUse: ast-comprehend-hook.sh (comprensión granular)
    └─► PostToolUse: ast-quality-gate-hook.sh (validación async)

[post-SDD] ACTUALIZACIÓN — /codemap:refresh --incremental
    └─► Solo regenera .acm de ficheros modificados
    └─► .dependency-graph.json rastrea qué .acm cubren qué fuentes
```

---

## Parte 4 — Mapas humanos (.hcm)

Los `.acm` resuelven el problema de los **agentes**: contexto estructurado, denso,
pre-cargado. Los `.hcm` (Human Code Maps) resuelven el problema de las **personas**:
la deuda cognitiva que se acumula cuando nadie documenta por qué el código existe.

Según Addy Osmani (2024), los desarrolladores pasan el **58% del tiempo leyendo**
código vs. el 42% escribiéndolo. La deuda cognitiva multiplica ese 58%.

### Formato .hcm

```markdown
# {Componente} — Human Map (.hcm)
> version: X.Y | last-walk: YYYY-MM-DD | walk-time: Xmin | debt-score: N/10
> acm-sync: .agent-maps/{componente}.acm

## La historia
Qué problema resuelve. En lenguaje humano, no en términos de ficheros.

## El modelo mental
Cómo pensar en este componente. Analogías. Qué lo hace diferente.

## Puntos de entrada
- Para hacer X → empieza en fichero:sección

## Gotchas
- Lo que sorprende a los devs nuevos

## Por qué está construido así
- Decisiones de diseño y trade-offs aceptados

## Indicadores de deuda
- Áreas conocidas de confusión o refactor pendiente
```

### Debt Score (0–10)

```
debt_score =
  min((days_since_last_walk / 30) * 2, 4)   # Stale penalty (max 4)
  + complexity_indicator                      # 0-3 (acoplamiento)
  + (1 - test_coverage_ratio) * 3             # Coverage gap (max 3)

0-3: Mapa fresco
4-6: Revisar pronto
7-10: Deuda activa — está costando dinero ahora
```

### Ubicación por proyecto

Cada proyecto gestiona sus propios mapas dentro de su carpeta:

```
projects/{proyecto}/
├── CLAUDE.md
├── .human-maps/               ← Mapas narrativos para desarrolladores
│   ├── {proyecto}.hcm         ← Mapa general del proyecto
│   └── _archived/             ← Componentes eliminados o fusionados
└── .agent-maps/               ← Mapas estructurales para agentes
    ├── {proyecto}.acm
    └── INDEX.acm
```

El directorio `.human-maps/` raíz del workspace contiene únicamente los mapas
del propio pm-workspace como producto (no de los proyectos gestionados).

### Ciclo de vida

```
Creación (/codemap:generate-human) → Validación humana → Activo
         ↓ código cambia
      .acm se regenera → .hcm marcado stale → Refresh (/codemap:walk)
```

**Regla inmutable:** Un `.hcm` nunca puede tener `last-walk` más reciente que su `.acm`.
Si el `.acm` es stale, el `.hcm` también lo es independientemente de su fecha.

### Comandos

```bash
# Generar borrador .hcm desde .acm + código
/codemap:generate-human projects/mi-proyecto/

# Sesión guiada de re-lectura (refresh)
/codemap:walk mi-modulo

# Ver debt-scores de todos los .hcm del proyecto
/codemap:debt-report

# Forzar refresh del .hcm indicado
/codemap:refresh-human projects/mi-proyecto/.human-maps/mi-modulo.hcm
```

---

## Comandos disponibles

```bash
# Comprensión de un fichero
bash scripts/ast-comprehend.sh src/Services/AuthService.cs

# Comprensión de un directorio completo
bash scripts/ast-comprehend.sh src/Module/ --output output/map.json

# Modo surface-only (rápido, para hook)
bash scripts/ast-comprehend.sh src/File.cs --surface-only

# Modo legacy (sin umbrales, documenta todo)
bash scripts/ast-comprehend.sh src/Legacy/ --legacy-mode --output output/legacy.json

# Quality Gate de un fichero
bash scripts/ast-quality-gate.sh src/Services/OrderService.cs

# Quality Gate de un directorio (verifica todo el módulo)
bash scripts/ast-quality-gate.sh src/Module/
```

---

## Garantías del sistema

1. **Nunca bloquea un edit**: RN-COMP-02 — si la comprensión falla, exit 0 siempre
2. **Nunca destruye código**: RN-COMP-02 — comprensión es read-only
3. **Siempre tiene fallback**: RN-COMP-05 — grep-structural garantiza cobertura mínima
4. **Criterios agnósticos**: los 12 QG aplican igual a todos los lenguajes
5. **Schema unificado**: todos los outputs son comparables entre lenguajes

---

## Referencias

- Skill comprensión: `.opencode/skills/ast-comprehension/SKILL.md`
- Skill calidad: `.opencode/skills/ast-quality-gate/SKILL.md`
- Hook comprensión: `.opencode/hooks/ast-comprehend-hook.sh`
- Hook calidad: `.opencode/hooks/ast-quality-gate-hook.sh`
- Script comprensión: `scripts/ast-comprehend.sh`
- Script calidad: `scripts/ast-quality-gate.sh`
- Reglas Semgrep: `.opencode/skills/ast-quality-gate/references/semgrep-rules.yaml`
- Schema comprehension: `.opencode/skills/ast-comprehension/references/comprehension-schema.md`
- Skill mapas de código: `.opencode/skills/agent-code-map/SKILL.md`
- Schema quality: `.opencode/skills/ast-quality-gate/references/unified-schema.md`
- Regla mapas humanos: `docs/rules/domain/hcm-maps.md`
- Skill mapas humanos: `.opencode/skills/human-code-map/SKILL.md`
- Mapas del workspace: `.human-maps/`
- Mapas de proyectos: `projects/*/.human-maps/*.hcm`
