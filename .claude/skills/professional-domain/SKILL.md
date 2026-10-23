---
layer: peripheral
name: professional-domain
description: "Índice de las skills de dominio profesional (controlling, finanzas, laboral, legal, ventas). Usar cuando una tarea pide criterio de uno de esos dominios, para cargar la skill concreta."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.context_tier: L3
---

# professional-domain — Family Index

This directory contains professional-domain skills organized by family:

- `controlling/` — KPI analysis, variance reports, management reporting
- `finance/` — cash flow, investment analysis, financial reports
- `labour/` — Spanish labour law, onboarding/offboarding, conflict resolution
- `legal/` — contracts, compliance (ES), legal document drafting
- `sales/` — account research, pipeline analysis, proposals, objection handling

## Usage

Load the specific skill you need from its subdirectory:

```
.opencode/skills/professional-domain/labour/labour-conflict-resolver/SKILL.md
.opencode/skills/professional-domain/legal/legal-contract-reviewer/SKILL.md
```

This index file exists to satisfy workspace structure invariants.
Individual skills are in their respective family directories.
