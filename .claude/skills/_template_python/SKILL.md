---
layer: peripheral
name: _template_python
description: "TEMPLATE de skill Python-backed (SE-347/PMA). Usar cuando se copia este directorio para crear una skill que expone funcionalidad invocable con run(). NO se carga en runtime."
metadata:
  savia.maturity: stable
---

# _template_python — Template de skill Python-backed (SE-347 lección PMA)

> Copia este directorio a `.claude/skills/<nombre-skill>/` cuando el skill deba
> exponer **código reutilizable invocable** (no solo instrucciones). El patrón
> Python-backed viene de Prime Agent (docs/skills.md): SKILL.md + paquete
> Python instalable + callable `run()` con contrato tipado.
>
> Para skills solo-instructivos usa `.claude/skills/_template/`.

## Estructura

```
<nombre-skill>/
├── SKILL.md          # metadata + instrucciones (igual que markdown skill)
├── pyproject.toml    # marca el skill como python-backed
├── DOMAIN.md         # (opcional, pm-workspace) contexto de dominio
└── src/
    └── <import_name>/     # nombre con guiones → guiones bajos
        └── __init__.py    # debe definir `run(...)` (async opcional)
```

## Contrato (convención adoptada de PMA)

1. `SKILL.md` es obligatorio y sigue el estándar Agent Skills (agentskills.io).
2. `pyproject.toml` declara el paquete; el nombre de import es el nombre del
   skill con `-` → `_`.
3. `src/<import_name>/__init__.py` define `run(...)` — el punto de entrada que
   el agente llama con contrato tipado (args con nombres y defaults).
4. El callable se invoca desde el runtime de python del proyecto (venv local,
   CRIT-001: nada sale a cloud).
5. CLI opcional: declarar `[project.scripts]` en `pyproject.toml` para invocar
   desde shell.

## Ejemplo de `__init__.py`

```python
"""Ejemplo: skill python-backed 'release-audit'."""

async def run(repository: str, target_version: str) -> str:
    """Audita un release: devuelve resumen tabular local."""
    # implementación local (sin red / infra propia)
    return f"audit {repository}@{target_version} OK"
```

## Reglas pm-workspace

- CRIT-001: el código del skill se ejecuta en infraestructura propia; no se
  añaden dependencias sin aprobación (autonomous-safety).
- El SKILL.md debe documentar el contrato `run(...)` en `## Usage`.
- Verificar con `bash scripts/skill-catalog-auditor.sh --skill <nombre>`.
