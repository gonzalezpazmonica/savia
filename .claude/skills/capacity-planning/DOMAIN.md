# Capacity Planning — Domain Context

## Why this skill exists

Teams have limited capacity; sprints have fixed duration. Without explicit capacity planning, PMs over-commit, devs burn out, projects miss deadlines. Capacity planning answers: "How many story points can we safely deliver this sprint?" and "Who is overloaded/idle?"

## Domain concepts

- **Available Capacity** — Team hours per sprint = (headcount × hours/day × days in sprint) × focus_factor (0.75)
- **Committed Capacity** — Sum of hours estimated in sprint tasks
- **Focus Factor** — Ratio of productive hours to total hours (typically 0.75; accounts for meetings, interrupts, admin)
- **Velocity** — Story points completed per sprint; trend over time predicts future capacity
- **Overload threshold** — Utilization > 100% → overloaded; 85-100% → at the limit (`scripts/capacity-calculator.py`)

## Business rules it implements

- **RN-CAP-01**: Committed ≤ Available (never exceed capacity)
- **RN-CAP-02**: Alert if any dev ≥ 85% capacity (AL LÍMITE) and flag > 100% (SOBRE-CARGADO)
- **RN-CAP-03**: Velocity forecast based on last 5 sprints (not arbitrary estimates)
- **RN-CAP-04**: Capacity includes on-call, support, learning time (not just feature work)

## Relationship to other skills

**Upstream:** `pbi-decomposition` provides Task hour estimates; team structure (equipo.md) provides headcount
**Downstream:** `sprint-management` uses capacity plan to build sprint board; `reporting` uses velocity trends
**Parallel:** `team-workload` monitors capacity in real-time during sprint

## Key decisions

- **Focus factor 0.75 default** — Based on industry research; tweakable per team if they track actual productive hours
- **Velocity trend** — Don't plan off last sprint alone. Use 5-sprint rolling average for stability.
- **Proactive warnings** — Alert at 85% capacity (yellow), flag > 100% (red); the script never blocks, it reports
