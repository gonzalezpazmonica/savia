# Savia (pm-workspace) — OpenCode entrypoint
# ── Este fichero solo redirige al canónico ─────────────────────────────────

> **Fuente única de verdad**: `../CLAUDE.md` (raíz del workspace).
> OpenCode carga este fichero, lee la delegación y aplica el CLAUDE.md raíz.

---

## Modelo arquitectónico (importante)

`.opencode/` **no es** una copia paralela de `.claude/`. Es un **frontend** que
comparte la mayoría de recursos vía symlinks:

```
.opencode/
├── .claude     → symlink a ../.claude
├── commands    → symlink a ../.claude/commands  (559 commands)
├── hooks       → symlink a ../.claude/hooks     (102 hooks)
├── skills      → symlink a ../.claude/skills    (98 skills)
├── docs        → symlink a ../docs
├── agents/     ← DIRECTORIO REAL (70 agents, frontmatter adaptado a OpenCode)
├── plugins/    ← DIRECTORIO REAL (OpenCode plugin model)
└── mcp-templates/, install.sh, init-pm.sh, package.json, ...
```

Por tanto, cuando ves una referencia `.claude/foo` desde `.opencode/`, apunta
al mismo fichero físico que `../.claude/foo`. Ambas rutas son válidas.

**Lo único genuinamente independiente**: `.opencode/agents/*.md` (frontmatter
distinto: model alias `heavy|mid|fast`, permission L0-L4, plugin hooks).

---

## Qué hace OpenCode con este workspace

- Lee `AGENTS.md` y `SKILLS.md` en la raíz (mirror cross-frontend de `.opencode/agents/` y `.opencode/skills/`).
- Aplica el CLAUDE.md raíz como instrucciones del agente principal.
- Ejecuta hooks del `.claude/settings.json` cuando se invoca vía `claude` shell.
- Bajo OpenCode nativo (sin shell Claude), los hooks se ejecutan vía plugin TS — ver `plugins/`.

---

## Counters actuales (auto-generados)

| Recurso | Total | Fuente |
|---|---|---|
| Agents | 81 | `.opencode/agents/*.md` |
| Commands | 566 | `scripts/count-commands.sh` |
| Hooks | 102 | `.claude/hooks/*.sh` |
| Skills | 119 | `.claude/skills/*/SKILL.md` |

Drift check: `bash scripts/claude-md-drift-check.sh`.

---

## Para devs nuevos

1. Lee `../CLAUDE.md` primero — reglas críticas, identidad de Savia, lazy reference.
2. Lee `../AGENTS.md` y `../SKILLS.md` — catálogos cross-frontend.
3. Si vas a editar agentes/skills/commands: edita en `.claude/` (la raíz real).
4. Si vas a editar agentes OpenCode-específicos: edita en `.opencode/agents/`.
5. Después de cualquier cambio: `bash scripts/claude-md-drift-check.sh`.

---

## Compatibilidad cross-frontend

- **Claude Code nativo** → lee `../CLAUDE.md` + `.claude/settings.json` (hooks completos).
- **OpenCode v1.14+** → lee este fichero + `../AGENTS.md` + `../SKILLS.md` (plugins TS).
- **OpenCode-Copilot Enterprise** → lee `../AGENTS.md` + `../SKILLS.md` (sin hooks, sin slash commands).
- **LocalAI emergency (SPEC-122)** → lee `../CLAUDE.md` (Claude Code shell con base URL local).

Detalle: `docs/rules/domain/provider-agnostic-env.md`.

---

## Lo que NO está aquí

- Configuración (PAT, sprint duration, model aliases): `docs/rules/domain/pm-config.md` + `.claude/rules/pm-config.local.md`.
- Reglas críticas 1-25: `../CLAUDE.md` (inline 1-8) + `docs/rules/domain/critical-rules-extended.md` (9-25).
- Identidad de Savia: `../.claude/profiles/savia.md`.
- Catálogo de agentes: `docs/rules/domain/agents-catalog.md`.
- Catálogo de comandos: `docs/rules/domain/pm-workflow.md`.

---

## Histórico

Versiones anteriores de este fichero duplicaban configuración y reglas del
CLAUDE.md raíz. Esa duplicación generaba drift sistemático (counters
desactualizados, reglas obsoletas). Desde SE-100 (2026-05-27), este fichero
solo redirige al canónico y describe el modelo arquitectónico real
(symlinks shared). No añadas configuración aquí — añádela en la raíz.
