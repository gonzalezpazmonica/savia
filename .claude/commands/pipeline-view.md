---
name: pipeline-view
description: ASCII table of all active pursuits with stage, value, and probability
argument-hint: "[--stage qualification|proposal|won] [--tenant tenant-id]"
context_cost: low
model_tier: fast
allowed-tools: [Bash, Read, Glob, Grep]
tier: core
---

# /pipeline-view — Opportunity pipeline dashboard (SE-015)

**Argumentos:** `$ARGUMENTS` (optional filters)

## Flujo

1. Scan for pipeline directories: `tenants/*/pipeline/pursuits/` and `projects/*/pipeline/pursuits/`
2. For each pursuit.md, extract frontmatter: opp_id, client, title, stage, estimated_value_eur, probability_pct
3. If --stage provided, filter by that stage
4. If --tenant provided, filter by tenant
5. Sort by stage priority (negotiation > proposal > pursuit > qualification > lead), then by value descending
6. Render ASCII table

## Output format

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Pipeline View — {tenant or "All tenants"}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  OPP-ID          Client        Stage          Value EUR    Prob
  ─────────────── ───────────── ────────────── ──────────── ────
  OPP-2026-001    megabank-eu   negotiation    1,200,000    75%
  OPP-2026-003    pharma-nord   proposal         800,000    50%
  OPP-2026-002    telco-south   qualification    350,000    35%

  Total pipeline: 2,350,000 EUR | Weighted: 837,500 EUR
  Active pursuits: 3 | Won YTD: 0 | Lost YTD: 0
```

If no pursuits found, show:
```
  No active pursuits found.
  Start with: /pursuit-init "Client" "Title"
```

## Banner de fin

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  /pipeline-view — Completado
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```
