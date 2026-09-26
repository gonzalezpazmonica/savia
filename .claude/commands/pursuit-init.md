---
name: pursuit-init
description: Scaffold a new pursuit opportunity directory with template files
argument-hint: '"Client Name" "Opportunity Title" [--tenant tenant-id]'
context_cost: low
model_tier: fast
allowed-tools: [Bash, Write, Read]
tier: core
---

# /pursuit-init — Create a new pursuit (SE-015)

**Argumentos:** `$ARGUMENTS` — expects "Client Name" "Title" and optional --tenant

## Flujo

1. Parse client name and title from arguments
2. Generate OPP-ID: `OPP-{YYYY}-{NNN}` (next sequential from existing)
3. Determine tenant (from --tenant flag or active project)
4. Create directory: `tenants/{tenant}/pipeline/pursuits/OPP-{YYYY}-{NNN}/`
5. Scaffold files:
   - `pursuit.md` with YAML frontmatter (all required fields, stage=lead)
   - Empty `qualification.yaml` stub
   - Empty `bid-decision.md` stub
6. Create `tenants/{tenant}/pipeline/` and `library/` dirs if missing

## Template pursuit.md

```yaml
---
opp_id: "{OPP-ID}"
tenant: "{tenant}"
client: "{client}"
title: "{title}"
stage: "lead"
engagement_type: "time-and-materials"
estimated_value_eur: 0
probability_pct: 10
source: "inbound"
practice: ""
pursuit_team:
  - role: "account-executive"
    handle: "@tbd"
pre_sales_budget_hours: 0
pre_sales_spent_hours: 0
next_milestone:
  what: "Initial qualification"
  when: "{today+14}"
---

# {title}

Client: {client}
```

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pursuit-init — Completado
  Pursuit: {OPP-ID} — {title}
  Path: tenants/{tenant}/pipeline/pursuits/{OPP-ID}/
  Next: /pursuit-qualify {OPP-ID}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
