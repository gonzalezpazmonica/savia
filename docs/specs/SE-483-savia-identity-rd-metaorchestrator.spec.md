---
status: APPROVED
priority: P1
developer_type: agent-single
created: 2026-10-30
approved_at: 2026-10-30
author: Savia
phase: D
risk: L2
related_specs: [SPEC-185, SE-269, SE-484]
origin: decisión de la operadora 2026-10-30 — Savia pasa de «PM automatizada con IA» a «metaorquestadora agéntica de I+D+i». AskUserQuestion: alcance «identidad y flujos» (sin renombrar pm-workspace), gestión de proyectos como capacidad (no propósito), frase canónica «Metaorquestadora I+D+i».
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-483 — Identidad: Savia, metaorquestadora agéntica de I+D+i

## Problema

Savia nació como workspace de ayuda a project managers y la documentación funcional sigue diciéndolo. Hoy coordina:

- harnesses especializados: Yema, revisoras independientes y proveedores externos;
- líneas de investigación;
- cúpulas de conocimiento gobernado (Savia Vaults);
- Savia Space;
- y, como una capacidad más, la gestión de proyectos.

El inventario de 2026-10-30 encontró:

- **38 superficies de identidad nuclear**, con cuatro versiones distintas de «qué es Savia». CLAUDE.md, AGENTS.md, el plugin y el onboarding dicen «PM»; el README, `llms.txt` y GitHub dicen «soberano/gobernado».
- **16 conversaciones preprogramadas** con encuadre PM. Ejemplos: la presentación de primera sesión (con un emoji, contra la regla de savia.md) y el banner `PM-Workspace Init` del arranque.
- **15 flujos** que asumen PM y sprints como propósito principal.

## Frase canónica (única fuente)

> Savia es una metaorquestadora agéntica de I+D+i: coordina agentes y harnesses especializados, líneas de investigación, cúpulas de conocimiento gobernado y proyectos, con la autoridad siempre en la persona. Open source y soberana.

Versión corta, para la descripción de GitHub, el plugin y `critical-facts`:

> Savia — metaorquestadora agéntica de I+D+i, open source y soberana.

**Fuente única:** `.claude/profiles/savia.md`, sección `## Identidad canónica`, con las dos frases entre marcadores `<!-- identity:long -->` y `<!-- identity:short -->`. Los generadores leen de ahí. Ninguna otra superficie escribe su propia versión.

## Requisitos

### R1 — Generadores antes que ficheros generados

- `scripts/agents-md-generate.sh` (AGENTS.md), `scripts/generate-critical-facts.sh`, `scripts/llms-txt-generate.sh` (que pasa a cubrir también `llms.txt` de la raíz) y `scripts/slm-modelfile-gen.sh` (prompt de sistema de los modelos locales) leen la frase de la fuente única.
- Se regenera la salida. No se edita a mano un fichero generado.

### R2 — Superficies nucleares

**CLAUDE.md:**
- «Qué es» con la frase larga;
- «Rol» como metaorquestadora, con las capacidades: orquestación de harnesses, investigación (Labs), conocimiento (Vaults), Space, desarrollo con SDD y gestión de proyectos;
- las reglas de PM (1-3, 7) siguen inline como reglas del dominio de proyectos;
- en la tabla Lazy Reference, una fila de metaorquestación (harnesses, Yema, Labs).

Restricción: CLAUDE.md sigue ≤ 150 líneas y no crece más de 10.

**`.claude/profiles/savia.md`:**
- sección de identidad canónica;
- ejemplos de tono también de orquestación e I+D+i, no solo de sprints;
- la presentación sin emojis.

**README.md**, `docs/readme/01-introduccion.md`, `plugin.json` y `.claude-plugin/plugin.json` (descripción, keywords, categorías y cifras regeneradas o eliminadas si nadie las mantiene), `.opencode/CLAUDE.md` y `.opencode/README.md`.

**READMEs traducidos:**
- se retraducen desde README.md en la misma PR, si el worker puede hacerlo con calidad;
- si no, se marcan con `Last sync` y un aviso de desfase, y queda abierta una tarea.

**`docs/critical-facts.md`:**
- el hecho `Sprint: PM-Workspace…` pasa a `Identidad: <frase corta>`;
- el cap de 150 tokens se respeta;
- se actualizan el AC de SPEC-185 y `tests/test-critical-facts-cap.bats`, que exigían el campo `Sprint`.

### R3 — Conversaciones preprogramadas

- El banner de arranque `PM-Workspace Init` pasa a `Savia Init`, en las tres variantes de `session-init.sh`, y se actualizan los tests que lo comprueban (`tests/test-session-init.bats`, `tests/dual-cli/test_codex_events.py`).
- La presentación de primera sesión, el `/help` (orden de secciones: orquestación, investigación, conocimiento, desarrollo y proyectos) y `/onboard` siguen la nueva identidad.
- El contenido del onboarding lo rehace SE-484. Esta spec solo deja una única fuente para la presentación.

### R4 — Flujos y configuración

- `pm-config.md` y `pm-workflow.md` conservan su contenido, con el encuadre «dominio de gestión de proyectos».
- `docs/RESOLVER.md` y `agents-catalog.md` se agrupan por capacidad, con una sección de metaorquestación.
- La skill `savia-identity` deja de declarar `audience: pm` y su configuración de Azure DevOps pasa al dominio de proyectos.

### R5 — Lo que no cambia

- `pm-workspace` como identificador técnico: rutas, instalador, `~/.pm-workspace`, nombre del repo y URLs.
- Las reglas operativas de PM.
- La voz de Savia: femenina, sin emojis, Radical Honesty.
- Nada privado de Labs ni de la operadora en las superficies públicas. El marco Company as Code ya es público por su post.

## Criterios de aceptación

- **AC-1:** `git grep -n "PM automatizada\|AI project management\|Project Manager automatizado"` sobre CLAUDE.md, AGENTS.md, README.md, `docs/readme/01-*`, `plugin.json`, `.claude-plugin/`, `llms.txt`, `docs/llms*.txt`, `.claude/profiles/savia.md` y `profile-onboarding.md` devuelve 0.
- **AC-2:** la frase larga aparece literal en CLAUDE.md, AGENTS.md (generado), README.md y `llms.txt`. La corta, en `critical-facts.md` y `plugin.json`.
- **AC-3:** un test bats comprueba que cada superficie de AC-2 contiene la frase de la fuente única. Cambiar la fuente sin regenerar hace fallar el test.
- **AC-4:** `session-init.sh` imprime `Savia Init`; sus tests, actualizados, pasan.
- **AC-5:** `agents-md-drift-check`, `sam.py check`, `capability-entropy`, `validate-critical-facts-cap`, el test de equality-shield (CLAUDE.md ≤ 150 líneas) y `validate-ci-local.sh --quick` en verde.
- **AC-6:** ningún identificador técnico `pm-workspace` cambia (diff revisado: solo cambia texto descriptivo).
- **AC-7:** la descripción del repo en GitHub queda propuesta en la PR (orden `gh repo edit` lista). La aplica la operadora.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Identidad | CLAUDE.md + `.claude/profiles/savia.md` | AGENTS.md generado + `.opencode/CLAUDE.md` |
| Arranque | `session-init.sh` (SessionStart) | mismo script vía plugin savia-gates |
| Modelos locales | — | Modelfile de Ollama (`slm-modelfile-gen.sh`) |

### Verification protocol

- [ ] AGENTS.md regenerado contiene la frase canónica
- [ ] El banner de arranque es igual en ambos frontends
- [ ] Sin hooks nuevos

### Portability classification

- [x] **DUAL_BINDING**: los dos frontends leen la misma fuente vía generadores
