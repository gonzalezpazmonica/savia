---
context_tier: L2
token_budget: 530
---

# Regla: Workflow del dominio de gestión de proyectos — Convenciones, Cadencia y Comandos
# ── Referencia operativa compacta ────────────────────────────────────────────

> Dominio de gestión de proyectos: una capacidad de Savia, no su propósito.

##  Cadencia Scrum

| Ceremonia | Cuándo | Duración |
|---|---|---|
| Sprint Planning | Lunes inicio sprint, 10:00 | 4h max |
| Daily Standup | Cada día laborable, 09:15 | 15 min |
| Sprint Review | Viernes fin sprint, 15:00 | 1h |
| Retrospectiva | Viernes fin sprint, 16:30 | 1.5h |
| Refinement | Miércoles semana 1 del sprint, 11:00 | 2h |

##  Convenciones

- **Branches:** `feature/#XXXX-descripcion`, `fix/#XXXX-descripcion`
- **Commits:** `[AB#XXXX] Descripción corta en imperativo`
- **Sprints:** `Sprint YYYY-NN` (ej: `Sprint 2026-04`)
- **Informes:** `YYYYMMDD-tipo-proyecto.ext`

##  Comandos Disponibles (571)

> Tabla completa: `.opencode/commands/references/command-catalog.md`
> Catálogo interactivo: `/help [filtro]`

**Categorías:** Sprint y Reporting (10), PBI y Discovery (8), SDD (5), Calidad y PRs (4), Equipo (3), Infra (7), Diagramas (4), Pipelines (5), Azure Repos (6), Governance (5), Legacy & Capture (3), Project Onboarding (5), DevOps Extended (5), Mensajería e Inbox (6), Company Savia (7), Savia Flow (5), Travel Mode (2), Conectores (12), Utilidades (4).

##  Referencias

- Reglas Scrum: `docs/reglas-scrum.md`
- KPIs: `docs/kpis-equipo.md`
- Plantillas: `docs/plantillas-informes.md`
- Política estimación: `docs/politica-estimacion.md`
- Queries WIQL: `.opencode/skills/azure-devops-queries/references/wiql-patterns.md`
- Product Discovery: `.opencode/skills/product-discovery/SKILL.md`
- SDD: `.opencode/skills/spec-driven-development/SKILL.md`
- Team Onboarding: `.opencode/skills/team-onboarding/SKILL.md`
- Diagramas: `.opencode/skills/diagram-generation/SKILL.md`
- Azure Pipelines: `.opencode/skills/azure-pipelines/SKILL.md`
- UX Feedback: `docs/rules/domain/command-ux-feedback.md`
- Context Health: `docs/rules/domain/context-health.md`
- Azure DevOps API v7.1: https://learn.microsoft.com/en-us/rest/api/azure/devops/
