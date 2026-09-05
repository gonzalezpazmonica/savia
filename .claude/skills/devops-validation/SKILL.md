---
layer: peripheral
name: devops-validation
description: Usar cuando se conecta un proyecto nuevo a Azure DevOps para validar su configuración Agile.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: azure-devops-operator
  savia.maturity: stable
  savia.category: devops
  savia.context: fork
  savia.context_cost: low
  savia.maturity: stable
  savia.priority: medium
  savia.summary: "Valida configuracion de Azure DevOps contra requisitos Agile ideales. Comprueba areas, iteraciones, campos custom, politicas de branch. Output: informe de gaps + plan de remediacion."
  savia.tags: "validation, azure-devops, agile, configuration"
---

# Skill: devops-validation

> Audits an Azure DevOps project to verify it matches pm-workspace's "ideal Agile" configuration. Generates a remediation plan for manual approval if mismatches are found.

**Prerequisite:** Read `.opencode/skills/azure-devops-queries/SKILL.md` first.

---

## When to Invoke

- PM connects a new project to pm-workspace (provides org URL, project, team, PAT)
- PM runs `/devops-validate --project {p} [--team {t}]`
- Before first `/sprint-status` or `/pbi-decompose` on a new project

---

## What Gets Validated

8 checks, in order — each returns PASS / WARN / FAIL:

| # | Check | What | FAIL if |
|---|---|---|---|
| 1 | Connectivity | PAT can reach org | HTTP != 200 |
| 2 | Project | Project name exists | Not found |
| 3 | Process | Template is Agile | Basic or CMMI |
| 4 | Types | Epic, Feature, US, Task, Bug | Any missing |
| 5 | States | New, Active, Resolved, Closed per type | Required state missing |
| 6 | Fields | StoryPoints, RemainingWork, etc. per type | Required field missing |
| 7 | Backlog | Hierarchy + bug behavior | — (WARN only) |
| 8 | Iterations | Sprints have dates | No iterations at all |

Full field/state mapping: → `references/ideal-agile-config.md`

---

## Running the Validation

```bash
scripts/validate-devops.sh \
  --project "ProjectName" \
  --team "ProjectName Team" \
  --output output/devops-validation.json
```

Returns JSON report to stdout and optionally to file.

---

## Interpreting Results

**All PASS** → Project is ready for pm-workspace. Proceed with `/sprint-status` or `/pbi-decompose`.

**Any WARN** → Non-blocking issues. WIQL queries will work but some fields may return null or behavior may differ. List warnings to PM with remediation steps.

**Any FAIL** → Blocking issues. Generate remediation plan for PM approval:
1. List each FAIL with its `remediation` field
2. Group by action type (process change, type addition, etc.)
3. All changes require manual execution in Azure DevOps UI
4. After PM applies changes → re-run `/devops-validate` to confirm

---

## Remediation Categories

| Category | Action Required | Where |
|---|---|---|
| Process template | Change to Agile | Organization Settings > Process |
| Missing types | Add via inherited process or migrate | Organization Settings > Process |
| Missing states | Customize via inherited process | Organization Settings > Process |
| Missing fields | Add to WIT layout | Organization Settings > Process > WIT |
| Bug behavior | Change to "as requirements" | Project Settings > Boards > Team config |
| No iterations | Create sprints with dates | Project Settings > Iterations |

---

## JSON Report Schema

```json
{
  "project": "PM-Workspace",
  "team": "PM-Workspace Team",
  "org": "https://dev.azure.com/OrgName",
  "timestamp": "2026-02-28T10:00:00Z",
  "summary": { "total": 8, "pass": 6, "fail": 1, "warn": 1 },
  "checks": [
    {
      "check": "process",
      "status": "FAIL",
      "message": "Process Basic not compatible",
      "remediation": "Organization Settings > Process > Change to Agile"
    }
  ]
}
```

---

## References

- `references/ideal-agile-config.md` — Complete field/state/type mapping
- `../azure-devops-queries/references/wiql-fields.md` — WIQL field reference
- Command: `/devops-validate`
- Scripts: `scripts/validate-devops.sh`, `scripts/validate-devops-checks.sh`
