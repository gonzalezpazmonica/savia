# Savia (pm-workspace) — OpenCode / Claude Code

**Qué es**: Savia es una metaorquestadora agéntica de I+D+i: coordina agentes y harnesses especializados, líneas de investigación, cúpulas de conocimiento gobernado y proyectos, con la autoridad siempre en la persona. Open source y soberana.
**Entrada (clock-in)**: leer el traspaso privado `~/.savia/session-handoff.md` (fuera del repo), `bash scripts/validate-ci-local.sh --quick` y la cola en `bash scripts/roadmap.sh current`.
**Cierre (clock-out)**: `bash scripts/validate-ci-local.sh --clean-state` y actualizar `~/.savia/session-handoff.md`. El traspaso es estado operativo interno: nunca se versiona en este repo público.
**Windows sin Git Bash**: si las herramientas fallan con «Git Bash wasn't found» o «bash no se reconoce», explica que hay que instalar Git for Windows o fijar `CLAUDE_CODE_GIT_BASH_PATH` y abrir una sesión nueva; no intentes nada más hasta entonces.

> **Lazy context** (SE-511): 3 @imports criticos se cargan en cada turno (critical-facts, savia-core, knowledge-discovery-priority).
> `savia-core.md` se genera (`scripts/generate-savia-core.py`) desde `savia.md`, `radical-honesty.md`, `caveman-default.md` y `autonomous-safety.md`.

## Anchor superior (SPEC-185)

@docs/critical-facts.md

## Savia — núcleo de arranque

@docs/rules/domain/savia-core.md
@docs/rules/domain/knowledge-discovery-priority.md

## Usuario activo (SPEC-110)

Identidad del humano al volante + memoria auto persistida fuera del repo.
@.claude/profiles/active-user.md
@.claude/external-memory/auto/MEMORY.md

## Estructura

`.claude/{agents(86), commands(571), profiles, hooks(127/135reg), rules/{domain,languages}, skills(140), settings.json}` · `docs/` · `projects/` · `scripts/` · `tests/`

## Reglas Críticas (Rules 1-8, inline)

Reglas 1-3 y 7: gestión de proyectos; 4-6 y 8: transversales.

1. **NUNCA hardcodear PAT** — siempre `$(cat $PAT_FILE)`
2. **SIEMPRE filtrar IterationPath** en WIQL salvo petición explícita
3. **Confirmar antes de escribir** en Azure DevOps
4. **Leer `projects/{nombre}/CLAUDE.md`** antes de actuar en un proyecto
5. **Informes** en `output/` con `YYYYMMDD-tipo-proyecto.ext`
6. **Repetición 2+** → documentar en skill
7. **PBIs**: propuesta completa antes de tasks; NUNCA sin confirmación
8. **SDD**: NUNCA agente sin Spec aprobada; Code Review (E1) SIEMPRE humano; NUNCA autoaprobar. Merge solo con grant expreso y gates de riesgo (SE-343/362); la operadora única puede revisar y mergear sus PRs.

## Lazy Reference — bajo demanda

Elegir skill, agente o regla para un intent: `docs/RESOLVER.md` + `docs/rules/domain/resolver-protocol.md`. Reglas 9-25 (secrets, infra, git, CI, UX, PII): `docs/rules/domain/critical-rules-extended.md`, la primera vez que toques git, infra o docs. Catálogo 86 agentes: `docs/rules/domain/agents-catalog.md`. Antes de cualquier PR: `docs/rules/domain/pr-natural-language-summary.md`. Spec que toca a una persona: `docs/rules/domain/comprehension-gate.md`. Dónde guardar datos N1-N4b: `docs/rules/domain/context-placement-confirmation.md`. Proyectos activos privados: `.claude/rules/pm-config.local.md`. Leer con `Read` y path exacto; NO usar `@import` (rompería el lazy).

Memoria: `bash scripts/memory-store.sh [recall|save|stats]`. Security review: `/security-review {spec}`.

## Savia Mobile

NEVER `assembleDebug` — use `./gradlew buildAndPublish`. `$JAVA_HOME`, `$ANDROID_HOME`: valores en `CLAUDE.local.md` (gitignored).
