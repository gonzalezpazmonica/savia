---
layer: peripheral
name: write-a-skill
description: Guia para crear una nueva skill correctamente en pm-workspace. Usar cuando una tarea se repite 2+ veces o tarda mas de 15 min.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: meta
  savia.maturity: stable
  savia.context: standalone
  savia.context_cost: low
  savia.maturity: stable
  savia.priority: medium
  savia.tags: "meta, skill-authoring, quality-gate"
  savia.trigger_keywords: "crea skill, nueva skill, write-a-skill, skill nuevo"
---

# Skill: Write a Skill

Guia canonica para crear una skill nueva en pm-workspace que supere el auditor de calidad.

## Authoritative Paths

> Lee estos paths antes de actuar.

| Para | Lee este path |
|---|---|
| Template SKILL.md | `.opencode/skills/_template/SKILL.md` |
| Template DOMAIN.md | `.opencode/skills/_template/DOMAIN.md` |
| Protocolo de template | `docs/rules/domain/skill-template-protocol.md` |
| Auditor de calidad | `scripts/skill-catalog-auditor.sh` |
| Registro de skills | `SKILLS.md` |

## Cuando usar

- Una tarea se repite 2+ veces en sesiones distintas.
- Una tarea tarda mas de 15 minutos y sigue un patron reutilizable.
- Un patron nuevo aparece que ningun skill existente cubre.

## Cuando NO usar

- La tarea es un comando puntual que no se repetira.
- Ya existe una skill con el mismo scope — ampliar la existente.
- La tarea es solo configuracion de proyecto (usar regla en `docs/rules/`).

## Decision Checklist

1. La tarea se ha repetido 2+ veces? Si NO: documenta como nota, no como skill.
2. Existe ya una skill solapada? Si SI: ampliar esa skill en lugar de crear una nueva.
3. El nombre es un verbo o patron de accion? Si NO: renombrar antes de crear.

### Abort Conditions

- Si la skill resultante superaria 150 lineas, dividirla en dos skills especializadas.
- Si no puedes rellenar `DOMAIN.md ## Por que existe esta skill` en 2 frases, la skill no deberia existir.

## Workflow

```
Detectar patron repetido
    |
Copiar template a .claude/skills/<nombre>/
    |
Rellenar SKILL.md y DOMAIN.md
    |
Verificar con auditor (debe dar OK)
    |
Registrar en SKILLS.md
```

### Detalle de cada paso

1. **Copiar template**:
   ```
   cp -r .claude/skills/_template .claude/skills/<nombre-skill>
   ```

2. **Rellenar SKILL.md**: sustituir todos los `<placeholder>`. Seguir patron "Authoritative Paths First" (SE-153). Borrar bloque HTML inicial. Si la skill no es orquestadora, borrar la seccion `Subagent Scope Guard`.

3. **Rellenar DOMAIN.md**: max 60 lineas. Cubrir: por que existe, conceptos de dominio, limites, confidencialidad, referencias.

4. **Verificar**:
   ```
   bash scripts/skill-catalog-auditor.sh --skill <nombre>
   ```
   Criterio PASS: SKILL.md existe, DOMAIN.md existe, frontmatter con name y description presentes, SKILL.md <= 150 lineas, DOMAIN.md <= 60 lineas, DOMAIN.md > 3 lineas, SKILL.md referencia al menos un path real.

5. **Registrar**: ejecutar `bash scripts/skills-md-generate.sh` para regenerar SKILLS.md.

## Outputs esperados

- `.claude/skills/<nombre>/SKILL.md` (<=150 lineas)
- `.claude/skills/<nombre>/DOMAIN.md` (<=60 lineas)
- `SKILLS.md` actualizado
- Auditor: resultado OK sin FAIL

## Dos tipos de skill (lección SE-347 / Prime Agent)

Decide el tipo ANTES de copiar el template:

| Tipo | Cuándo | Template | Contrato |
|---|---|---|---|
| Markdown (instrucciones) | La capacidad es sobre todo procedimiento | `.claude/skills/_template/` | SKILL.md guía al agente |
| **Python-backed** | El agente debe invocar funcionalidad reutilizable con contrato tipado | `.claude/skills/_template_python/` | SKILL.md + `pyproject.toml` + `src/<import>/__init__.py` con `run(...)` |

Reglas del tipo Python-backed:

1. El import name es el nombre del skill con `-` → `_` (ej. `release-audit` → `release_audit`).
2. `src/<import>/__init__.py` debe exponer `run(...)` (callable, async opcional).
3. `pyproject.toml` declara el paquete; `[project.scripts]` opcional para CLI.
4. Se instala en el venv de python del proyecto (local, CRIT-001 — nunca cloud).
5. El SKILL.md documenta el contrato en `## Usage` (args con nombres y defaults).
6. TDD: escribe el test del callable antes que la implementación (`__init__.test.py`).

Los skills de digestión/análisis (pdf-digest, excel-digest, tabular-analyst)
son candidatos a migrar a Python-backed progresivamente.

## Memory hooks

- Skill nueva creada: guardar en memoria con tipo decision y titulo "skill creada: nombre".

## Related

- Template: `.opencode/skills/_template/SKILL.md`
- Rule: `docs/rules/domain/skill-template-protocol.md`
- Auditor: `scripts/skill-catalog-auditor.sh`
- Roadmap: `docs/ROADMAP.md`
