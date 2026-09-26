---
name: plugin-export
description: Empaquetar pm-workspace como plugin distributable con validación de estructura
argument-hint: "[--components skills,agents,commands] [--output path]"
allowed-tools:
  - Read
  - Bash
  - Glob
model_tier: mid
context_cost: medium
tier: core
---

# /plugin-export

Empaqueta el workspace actual como plugin distributable para Claude Code.
Valida integridad de estructura, genera manifest dinámico, crea archivo comprimido.

## Uso

```
/plugin-export [--components skills,agents,commands] [--output /ruta]
```

### Argumentos

- `--components` (opcional): Exportar solo componentes específicos (default: todos)
  - `skills` — exportar directorio `.opencode/skills/`
  - `agents` — exportar directorio `.opencode/agents/`
  - `commands` — exportar directorio `.opencode/commands/`
  - `rules` — exportar directorio `docs/rules/`
  - Separar con comas: `skills,agents,commands`
- `--output` (opcional): Ruta del archivo de salida (default: `output/pm-workspace-plugin.tar.gz`)

### Ejemplos

```
/plugin-export
/plugin-export --components skills,commands
/plugin-export --components skills --output /tmp/skills-only.tar.gz
```

## Proceso

1. **Validación** — Verificar integridad (SKILL.md, frontmatter, líneas)
2. **Conteo** — Contar skills (45), agents (33), commands (400)
3. **Manifest** — Generar plugin.json dinámico con conteos reales
4. **Compresión** — Crear .tar.gz con componentes seleccionados
5. **Reporte** — Mostrar banner con resumen, ruta del archivo, siguientes pasos

## Output

Archivo comprimido en `output/pm-workspace-plugin-YYYYMMDD-HHMMSS.tar.gz`
con estructura:

```
pm-workspace-plugin/
├── .claude-plugin/plugin.json
├── .opencode/commands/
├── .opencode/skills/
├── .opencode/agents/
└── README.md
```

## Validación

- Cada skill tiene `SKILL.md` ≤ 150 líneas ✅
- Cada agent tiene frontmatter válido ✅
- Cada command tiene descripción y model ✅
- Sincronización de versión en CHANGELOG.md ✅
