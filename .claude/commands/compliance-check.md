---
name: compliance-check
description: Ejecuta todas las verificaciones de compliance de reglas
model_tier: fast
allowed-tools: ["Bash"]
context_cost: low
tier: core
---

# /compliance-check — Verificación de compliance de reglas

Ejecuta el sistema de verificación automática de reglas de pm-workspace.

## Qué verifica

1. **Links de comparación en CHANGELOG** — Cada `## [X.Y.Z]` debe tener su `[X.Y.Z]: URL` al final
2. **Tamaño de ficheros** — Commands, rules, skills ≤ 150 líneas
3. **Frontmatter YAML** — Comandos nuevos deben tener frontmatter
4. **READMEs** — Máximo 150 líneas, sincronización ES/EN

## Parámetros

- Sin parámetros: verifica ficheros staged
- `--all`: verifica todo el repositorio

## Ejecución

```bash
bash .claude/compliance/runner.sh --all
```

## Si hay violaciones

1. Lee el mensaje de error — indica qué regla se ha violado
2. Localiza la regla en `docs/rules/domain/` para entender el contexto
3. Corrige la violación
4. Vuelve a ejecutar `/compliance-check` para verificar

## Cómo funciona

El sistema traduce reglas de prosa (`docs/rules/domain/*.md`) a verificaciones ejecutables
(`.claude/compliance/checks/*.sh`). Así, aunque el LLM pierda contexto en conversaciones largas,
los scripts garantizan que las reglas objetivas se cumplen.

**Reglas cubiertas automáticamente:**

| Regla | Check | Tipo |
|-------|-------|------|
| `changelog-enforcement.md` | `validate-changelog-links.sh` | Bloqueante |
| File size conventions | `check-file-size.sh` | Bloqueante |
| Command validation | `check-command-frontmatter.sh` | Warning |
| README conventions | `check-readme-sync.sh` | Bloqueante |

Las reglas conversacionales (tone, workflow, inclusive-review) no son verificables por script
y siguen dependiendo del contexto cargado en las rules de Claude Code.
