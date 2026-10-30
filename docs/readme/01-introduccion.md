# Introducción a Savia

>  Soy Savia. Si acabas de llegar, esta página es para ti. En 5 minutos sabrás qué soy, qué puedo hacer por ti, y cómo empezar según tu rol.

---

## ¿Qué es esto?

Savia es una metaorquestadora agéntica de I+D+i: coordina agentes y harnesses especializados, líneas de investigación, cúpulas de conocimiento gobernado y proyectos, con la autoridad siempre en la persona. Open source y soberana.

Funciono sobre Claude Code, OpenCode o Codex (el repositorio se llama técnicamente `pm-workspace`). La gestión de proyectos es una de mis capacidades: sprints, backlog, infraestructura, facturación e informes — en 16 lenguajes, con Azure DevOps, Jira, o 100% Git-native (Savia Flow).

Mi característica más avanzada es el **Spec-Driven Development**: las tareas se documentan como contratos ejecutables, y un agente (o humano) las implementa siguiendo ese contrato.

---

## ¿Quién eres?

Tu experiencia conmigo depende de tu rol. Ve directamente a tu quick-start:

- **Tech Lead** → [quick-start-tech-lead](../quick-starts/quick-start-tech-lead.md)
- **Developer** → [quick-start-developer](../quick-starts/quick-start-developer.md)
- **PM / Scrum Master** → [quick-start-pm](../quick-starts/quick-start-pm.md)
- **QA** → [quick-start-qa](../quick-starts/quick-start-qa.md)
- **Product Owner** → [quick-start-po](../quick-starts/quick-start-po.md)
- **CEO / CTO** → [quick-start-ceo](../quick-starts/quick-start-ceo.md)

---

## Ejemplo — Primeros 5 minutos

_Escenario (dominio de proyectos): lunes por la mañana. Abres Claude Code / OpenCode en el workspace._

**Tú:** `¿Qué proyectos tengo y qué puedo hacer?`

**Savia:**
```
Tengo 2 proyectos activos:
  • ProyectoAlpha — equipo de 6, sprint 2026-04 activo
  • ProyectoBeta  — equipo de 4, precio fijo

Puedo ayudarte con:
  Sprint   → /sprint-status, /sprint-plan, /sprint-review
  Informes → /report-hours, /report-executive
  Backlog  → /pbi-decompose, /pbi-plan-sprint
  SDD      → /spec-generate, /agent-run

¿Por dónde empezamos? Si es lunes, te recomiendo /sprint-status.
```

**Tú:** `/sprint-status --project ProyectoAlpha`

**Savia:**
```
Sprint 2026-04 · ProyectoAlpha · Día 6/10
Burndown ████████░░░░░░░░ 40% WARN por debajo del plan

Items activos: 4
  AB#1021  POST /patients → Laura [3/5h]
  AB#1022  Unit tests     →  agente [ejecutando]
  AB#1023  Migración      → Diego [0/4h] WARN sin avance
  AB#1024  Swagger        →  agente [review]

FAIL AB#1023 lleva 2 días sin movimiento
FAIL Burndown al 40% en día 6 → riesgo de no completar
```

---

## Dónde estamos en la documentación

```
docs/
├── readme/
│   ├── 01-introduccion.md    ← ESTÁS AQUÍ
│   ├── 02-estructura.md      ← directorios y ficheros
│   ├── 03-configuración.md   ← PAT, constantes, setup
│   ├── 04-uso-sprint-*.md    ← sprints e informes
│   ├── 05-sdd.md             ← Spec-Driven Development
│   └── ...                   ← 13 secciones en total
├── quick-starts/             ← guías rápidas por rol
├── guides/                   ← 13 guías por escenario
└── data-flow-guide-es.md     ← cómo se conectan las partes
```

---

## Siguiente paso

Ve a tu [quick-start por rol](#quién-eres) o continúa con la [estructura del workspace](02-estructura.md).
