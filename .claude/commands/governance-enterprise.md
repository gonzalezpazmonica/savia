---
name: governance-enterprise
description: "Enterprise governance — audit trail, compliance checks, decision registry, certification"
allowed-tools: [Read, Glob, Grep, Write, Edit, Bash]
argument-hint: "[audit-trail|compliance-check|decision-registry|certify] [--user @handle] [--since YYYY-MM-DD] [--action type]"
model_tier: mid
context_cost: medium
tier: core
---

# /governance-enterprise — Gobernanza Empresarial

> Skill: @.opencode/skills/governance-enterprise/SKILL.md
> Config: @docs/rules/domain/governance-enterprise.md, @docs/rules/domain/audit-trail-schema.md

Auditoría de acciones, verificación de cumplimiento (GDPR/ISO/EU AI Act/AEPD), registry de decisiones y certificación de gobernanza.

## Subcomandos

### `/governance-enterprise audit-trail [--user @handle] [--since YYYY-MM-DD] [--action type]`

Queries sobre audit trail:
- Leer `.audit-trail/actions.jsonl` + archive histórico
- Filtrar por usuario, rango fechas, tipo acción, resultado
- Generar tabla + resumen estadístico
- Output: tabla de acciones + analytics

### `/governance-enterprise compliance-check`

Verificar cumplimiento de todos los controles:
- Evaluarmatriz de controles (GDPR, ISO, AI Act, AEPD)
- Calcular scores por control (0-100)
- Agregar por categoría
- Output: tabla scores + recomendaciones + remediation plan si needed

### `/governance-enterprise decision-registry [--list|--add|--validate]`

Gestionar decision registry:
- `--list`: mostrar decisiones activas + histórico
- `--add`: crear nueva decisión documentada
- `--validate`: verificar integridad del registry
- Output: lista decisiones o validación report

### `/governance-enterprise certify`

Generar certificación de cumplimiento:
- Ejecutar compliance-check
- Si todos los controles ≥ 80%: generar certificación
- Si alguno < 80%: mostrar gaps + remediation plan
- Output: certificación PDF + entrada en decision-registry

## Datos almacenados

```
.audit-trail/
├── actions.jsonl           # JSONL append-only (últimos 12 meses)
└── archive/
    ├── 2025-12.jsonl.gz
    ├── 2025-11.jsonl.gz
    └── ...

output/governance/
├── compliance-check-YYYYMMDD.md
├── certs/
│   └── compliance-cert-YYYYMM.pdf
└── reports/
    └── decision-registry.md
```

## Integración

| Comando | Relación |
|---|---|
| `/aepd-compliance` | Framework específico AEPD (gobierna agentes) |
| `/security-audit` | Auditoría profunda de seguridad |
| `/ai-risk-assessment` | Risk assessment EU AI Act |
