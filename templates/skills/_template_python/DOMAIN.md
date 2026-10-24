---
context_tier: L2
---

# DOMAIN: Template Python-backed

## Por qué existe este template

Modelo para skills que exponen funcionalidad reutilizable invocable (patrón
Python-backed de Prime Agent, SE-347): SKILL.md + paquete Python + `run()`.

## Conceptos de dominio

- Import name = nombre del skill con `-` → `_`.
- `src/<import>/__init__.py` expone `run(...)` (callable, async opcional).
- `pyproject.toml` declara el paquete; `[project.scripts]` opcional para CLI.
- Se instala en el venv de python del proyecto (local, CRIT-001).

## Límites

- Para skills solo-instructivos usa `templates/skills/_template/`.
- TDD: test del callable antes de la implementación (`__init__.test.py`).

## Confidencialidad

- Ejecución local; sin dependencias externas sin aprobación.
