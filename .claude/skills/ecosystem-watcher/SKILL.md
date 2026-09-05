---
layer: peripheral
name: ecosystem-watcher
description: Usar una vez al mes para detectar cambios relevantes en el ecosistema de herramientas externas.
allowed-tools: [Read, Bash, Write, WebFetch]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: tech-research-agent
  savia.maturity: stable
  savia.category: research
  savia.context: fork
  savia.disable-model-invocation: false
  savia.maturity: beta
  savia.priority: low
  savia.summary: "Monthly ecosystem intelligence. Tracks awesome-claude-code, awesome-agent-skills, awesome-mcp-servers, anthropics/skills, github/spec-kit, modelcontextprotocol/servers and Claude/OpenCode changelogs. Generates output/research-skills-update-{YYYY-MM}.md with classified signals. Read-only — no autonomous PRs."
  savia.tags: "watch, monthly, intelligence, awesome, cron"
  savia.user-invocable: True
---

# Skill: Ecosystem Watcher

> Vigilancia continua del ecosistema. Sin esto, cada vez que Savia necesita "estado del arte" alguien tiene que rehacer la investigación desde cero. SPEC-146.

## When to use

- Cron mensual (1º de mes 09:00 UTC) vía GitHub Action.
- Manual: cuando se quiere ver qué ha cambiado desde el último snapshot.
- Tras releases mayores del ecosistema (Claude Code update, OpenCode major).

## Inputs

- Watch list: `docs/rules/domain/ecosystem-watch-list.yaml`.
- Último snapshot timestamp: leído de `.savia-memory/ecosystem-snapshots/last-run.txt`.

## Workflow

1. **Cargar watch list** YAML con repos + docs.
2. **Para cada repo GitHub**:
   - `gh api repos/{owner}/{name}/commits?since={last_run}` → contar commits.
   - `gh api repos/{owner}/{name}/releases` → listar releases nuevos.
   - Guardar snapshot en `.savia-memory/ecosystem-snapshots/{slug}-{YYYY-MM}.md`.
3. **Para cada docs URL**:
   - `WebFetch` la URL.
   - Diff contra snapshot anterior si existe.
4. **Clasificar señales**:
   - **High**: cambios que tocan algún spec PROPOSED (cross-ref con `docs/propuestas/`).
   - **Medium**: relevantes sin acción inmediata.
   - **Low**: ruido informativo.
5. **Generar informe** `output/research-skills-update-{YYYY-MM}.md`.
6. **Anotar** una línea en `output/ecosystem-watcher-history.jsonl`.

## Fail-safe

- Repo inaccesible → log warning + skip, no abortar.
- Rate-limit GitHub → retry con backoff exponencial, máx 3 intentos.
- Snapshot corrupto → regenerar desde cero, marcar en informe.

## Output schema

```markdown
# Ecosystem watch — YYYY-MM

## High signal (acción recomendada)
- [repo/source]: descripción + ref a SPEC afectado

## Medium signal (informativo)
- ...

## Low signal (ruido)
- ...

## Stats
- repos checked: N
- repos failed: N
- docs checked: N
```

## Anti-patterns

- **NO** abrir PRs automáticos basados en hallazgos.
- **NO** modificar specs PROPOSED — solo cross-reference.
- **NO** consumir tokens de Claude para clasificación si un regex/grep funciona.

## Acceptance Criteria

Ver `docs/propuestas/SPEC-146-awesome-repos-monthly-watcher.md`.
