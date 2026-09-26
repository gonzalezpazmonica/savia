---
name: audit
description: Generate professional executive audit report for workspace reliability assessment
model_tier: mid
context_cost: medium
tier: core
---

Ejecutar auditoría integral del workspace PM y presentar hallazgos.

## Flujo

1. Ejecutar: `bash scripts/executive-audit.sh --markdown`
2. Leer fichero de reporte generado en `output/audit-report-YYYY-MM-DD.md`
3. Parsear scores y métricas
4. Presentar hallazgos clave al usuario (5-10 líneas máximo en chat)
5. Resaltar áreas de concern (score < 70 en dimensiones específicas)
6. Sugerir acciones de mejora concretas

## Presentación de Resultados

**Banner de inicio:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Executive Audit — PM-Workspace
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**Resumen ejecutivo (máx 8 líneas):**
- Trust Score global
- Confidence Level
- Top 3 fortalezas
- Top 3 áreas de improvement

**Tabla de dimensiones:**
| Dimensión | Score | Status |
|-----------|-------|--------|
| Composition & Scale | X/10 | ✅/⚠️/❌ |
| Quality Metrics | X/10 | ✅/⚠️/❌ |
| Security Posture | X/10 | ✅/⚠️/❌ |
| Maturity | X/10 | ✅/⚠️/❌ |
| Documentation | X/10 | ✅/⚠️/❌ |
| CI/CD | X/10 | ✅/⚠️/❌ |

**Áreas de concern (si score < 70 en alguna dimensión):**
```
🔴 CRÍTICO: [Dimensión] — [Problema] — Sugerir /comando-específico
🟡 ALTO: [Dimensión] — [Problema] — Sugerir acción
```

**Sugerencias de mejora:**
- Listar máx 5 acciones concretas ordenadas por impacto
- Incluir comando equivalente si existe (`/debt-track`, `/security-scan`, etc.)
- Estimación de esfuerzo (rápido < 30 min, medio 1-2h, largo > 2h)

**Fichero completo:**
```
📄 Reporte detallado: output/audit-report-YYYY-MM-DD.md
```

## Áreas de concern automáticas

Si detectas alguno de estos patterns en los datos, escalar como CRÍTICO:
- Score < 50 en cualquier dimensión
- Coverage < 60%
- Seguridad: vulnerabilities > 0
- Maturity: <30% stable skills
- Docs: <3/5 documentos requeridos

## Sugerencias de acciones

| Área | Problema | Acción Sugerida | Comando |
|------|----------|-----------------|---------|
| Calidad | Coverage < 80% | Aumentar test coverage | `/audit --focus tests` |
| Seguridad | Vulnerabilities > 0 | Ejecutar security scan | `/security-scan --detailed` |
| Madurez | >30% alpha skills | Plan de estabilización | `/skill-maturity --plan` |
| Docs | Docs < 3/5 | Documentar gaps | `/readme-update` |
| CI/CD | Jobs < 5 | Expandir pipeline | `.github/workflows/ci.yml` |

---

*Comando: `/audit` — Auditoría ejecutiva integral del workspace*
