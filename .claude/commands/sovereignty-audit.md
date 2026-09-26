---
name: sovereignty-audit
description: "Cognitive sovereignty audit — diagnose AI vendor lock-in risk and data portability"
allowed-tools: [Read, Glob, Grep, Write, Edit]
argument-hint: "[scan|report|exit-plan|recommend] [--format md|pdf] [--dimension d1|d2|d3|d4|d5]"
model_tier: mid
context_cost: medium
tier: core
---

# /sovereignty-audit — Auditoría de soberanía cognitiva

> Skill: @.opencode/skills/sovereignty-auditor/SKILL.md
> Config: @.opencode/skills/sovereignty-auditor/references/cognitive-sovereignty.md
> Complementa: @.opencode/commands/governance-audit.md

Diagnostica y cuantifica el nivel de independencia de tu organización respecto
a proveedores de IA. Basado en "La Trampa Cognitiva" (De Nicolás, 2026):
cuando la IA entiende tu organización mejor que tú, el coste de cambiar de
proveedor ya no es técnico — es estratégico.

## Subcomandos

### `/sovereignty-audit scan`

Escanea el workspace y calcula el Sovereignty Score (0-100):

**5 dimensiones analizadas:**
1. **D1 — Portabilidad de datos** (25%): formatos abiertos, SaviaHub, BacklogGit
2. **D2 — Independencia LLM** (25%): Emergency Mode, multi-modelo, prompts portables
3. **D3 — Protección del grafo** (20%): cifrado, PII gate, datos sensibles
4. **D4 — Gobernanza del consumo** (15%): políticas, audit trail, tracking
5. **D5 — Opcionalidad de salida** (15%): documentación, exit plan, backups

Output: score por dimensión + score global + clasificación + gráfico ASCII.
Resultado guardado en `output/sovereignty-scan-YYYYMMDD.md`.

### `/sovereignty-audit report [--format md|pdf]`

Informe ejecutivo de soberanía para CTO/CIO/comité de dirección:
- Score global + tendencia temporal (si hay scans anteriores)
- Desglose por dimensión con evidencia concreta
- Benchmarks contra configuración ideal de pm-workspace
- Riesgos priorizados con impacto estimado
- Recomendaciones top-3

### `/sovereignty-audit exit-plan`

Plan de salida concreto y documentado:
- Inventario de datos organizacionales (SaviaHub, perfiles, memorias, backlogs)
- Dependencias del proveedor actual (APIs, integraciones, MCP servers)
- Estimación de esfuerzo de migración por categoría
- Timeline realista (72h mínimo viables vs plan completo)
- Alternativas de proveedor disponibles

### `/sovereignty-audit recommend`

Recomendaciones accionables para mejorar el Sovereignty Score:
- Ordenadas por impacto/esfuerzo (quick wins primero)
- Con comandos concretos de pm-workspace
- Ejemplo: "Emergency Mode no configurado → `/emergency-mode setup`"
- Solo dimensiones con score < 70

## Clasificación del Sovereignty Score

| Rango | Nivel | Significado |
|---|---|---|
| 90-100 | Soberanía plena | Migración trivial |
| 70-89 | Soberanía alta | Migración viable con esfuerzo moderado |
| 50-69 | Riesgo medio | Dependencias significativas |
| 30-49 | Riesgo alto | Lock-in cognitivo en progreso |
| 0-29 | Lock-in crítico | Migración prácticamente inviable |

## Integración

- **governance-audit**: cumplimiento normativo (NIST, EU AI Act, AEPD)
- **sovereignty-audit**: independencia del proveedor (5 dimensiones)
- Ambos se complementan: cumplir la ley ≠ ser independiente

## Ejemplo de output (scan)

```
══════════════════════════════════════════
  Sovereignty Score: 78/100 — Soberanía alta
══════════════════════════════════════════

  D1 Portabilidad     ████████████████████░░░░░  82
  D2 Independencia    ██████████████████░░░░░░░  72
  D3 Grafo org.       █████████████████████░░░░  85
  D4 Gobernanza       ██████████████░░░░░░░░░░░  58
  D5 Salida           ████████████████████░░░░░  80

  ⚠️ D4 bajo 70 → Ejecuta /governance-policy create
  ✅ Migración viable con esfuerzo moderado
```

## Señales de alarma

El scan detecta automáticamente estas señales:
- No hay exit plan documentado
- Emergency Mode no configurado
- Datos sensibles en commits públicos
- Sin governance policy ni audit trail
- Documentación dispersa o incompleta
