---
name: comprehension-audit
description: Scan recent implementations and identify which lack comprehension reports. Report coverage and recommendations.
argument-hint: "[project-name]"
allowed-tools:
  - Glob
  - Grep
  - Read
model_tier: fast
context_cost: low
tier: core
---

# /comprehension-audit

Audit your project to identify which recent implementations lack mental model comprehension reports. Generates coverage report and prioritization recommendations.

## Usage

```
/comprehension-audit {project-name}
```

### Arguments

- `{project-name}` (required): Project directory name
  - Example: `sala-reservas`, `pm-workspace`, `api-gateway`

## Output

```
📋 Comprehension Coverage Audit
├─ Project: sala-reservas
├─ Tasks analyzed: 12 (completed last 30 days)
├─ Reports found: 4 (33%)
├─ Reports missing: 8 (67%) ← Priority for action
│
├─ MISSING REPORTS (prioritized by risk):
│  1. 🔴 AB#2891 — Auth service refactor (HIGH: security-critical)
│  2. 🟡 AB#2847 — Reservation algorithm (MEDIUM: complex logic)
│  3. 🟡 AB#2834 — Database migration (MEDIUM: infrastructure)
│  4. 🟢 AB#2823 — UI component (LOW: cosmetic)
│
├─ Coverage by sprint:
│  Sprint 2026-03: 50% (3/6 have reports)
│  Sprint 2026-02: 100% (6/6 have reports)
│  Sprint 2026-01: 0% (0/3 have reports) ← Retroactive action?
│
└─ Recommendation:
   Generate reports for AB#2891 (security) and AB#2847 (logic) first.
   Use /comprehension-report {task-id} to create each.
```

## What Gets Audited

For each completed task in the last 30 days (configurable):

- ✅ Does a mental model report exist?
- ✅ Is the report current (updated within 7 days of task completion)?
- 🔲 Task risk level (inferred: security/critical/normal)
- 🔲 Code complexity (lines changed, modules touched)
- 🔲 Test coverage of the implementation

## Criteria for "Missing"

A comprehension report is considered **missing** if:
- Task completed >3 days ago AND no report exists, OR
- Report exists but is >30 days old (stale), OR
- Code changed significantly since report was generated

## Priority Scoring

Risk assessment (for prioritization):

| Criterion | Points | Examples |
|---|---|---|
| Security-critical area | +20 | Auth, encryption, data access |
| > 200 lines changed | +15 | Large refactors, new features |
| > 3 modules touched | +10 | Cross-module changes |
| No tests written | +10 | Legacy code paths |
| External dependency | +5 | Third-party service integration |

High score = high priority for mental model.

## Usage Examples

**Recent project:**
```
/comprehension-audit sala-reservas
```

**Identify gaps across all projects:**
```
/comprehension-audit *
```
(Shows summary across all projects in `projects/`)

## Integration

Part of post-implementation quality assurance:

```
Task complete
  → /test-runner AB#1234        [verify tests pass]
  → /code-audit AB#1234         [verify code quality]
  → /comprehension-report AB#1234 [capture mental model]
  → /board-flow --mark-done     [update board]
```

**Retroactive audit:**
```
/comprehension-audit sala-reservas
→ Identifies missing reports
→ /comprehension-report AB#2891  [create report]
→ /comprehension-audit sala-reservas [refresh coverage]
```

## Output Saved

Coverage report saved to:
```
output/audits/YYYYMMDD-comprehension-audit-{project}.md
```

Contains: full task list, coverage percentages, prioritized missing reports, recommendations.

**Siguiente paso:** Generar reportes faltantes usando `/comprehension-report` para las tareas prioritarias.
