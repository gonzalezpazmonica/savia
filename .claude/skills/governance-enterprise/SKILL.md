---
layer: peripheral
name: governance-enterprise
description: "Usar cuando se audita compliance, se registran decisiones o se certifican procesos enterprise."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: governance
  savia.context: fork
  savia.context_cost: medium
  savia.dependencies: 
  savia.maturity: stable
  savia.memory: project
  savia.priority: high
  savia.summary: "Gobernanza empresarial: audit trail, verificacion de compliance, registro de decisiones y workflow de certificacion. Output: informes ISO 42001, EU AI Act, NIST AI RMF."
  savia.tags: "governance, audit-trail, certification, enterprise"
---

# Skill: Enterprise Governance

> Prerequisito: @docs/rules/domain/governance-enterprise.md, @docs/rules/domain/audit-trail-schema.md

Orquesta auditoría trail, verificación de cumplimiento (GDPR/ISO/AI Act/AEPD), registry de decisiones y certificación.

## Flujo 1 — Audit Trail (`audit-trail`)

1. Leer `.audit-trail/actions.jsonl` (activo) + archive/YYYY-MM.jsonl (histórico)
2. Permitir queries por: usuario, rango fechas, tipo acción, target
3. Generar resumen: total acciones, distribution por tipo, failures
4. Output: tabla de acciones + query stats

**Query examples**:
```
/governance-enterprise audit-trail --user @monica --since 2026-02-01
/governance-enterprise audit-trail --action delete --from 2026-01 --to 2026-03
/governance-enterprise audit-trail --target pbi --result failure
```

## Flujo 2 — Compliance Check (`compliance-check`)

1. Leer governance-enterprise.md (matriz de controles)
2. Por cada control: verificar evidencia más reciente
3. Calcular score por control (0-100 basado en fecha de última ejecución):
   - Fresh (< 30 días) = 100
   - Valid (31-90 días) = 75
   - Stale (91-180 días) = 50
   - Missing (> 180 días) = 0
4. Agregar por categoría (GDPR, ISO, AI, AEPD)
5. Generar `output/governance/compliance-check-YYYYMMDD.md`
6. Output: tabla scores + recomendaciones + remediation plan si needed

## Flujo 3 — Decision Registry (`decision-registry`)

1. Leer decision-registry.md
2. Por cada decisión: validar que tiene evidencia en file system
3. Listar decisiones activas + superseded + revoked
4. Detectar decisiones sin evidencia (gap warning)
5. Generar resumen: total decisiones, distribution por status
6. Output: registry formatted + gaps + next decisions needed

## Flujo 4 — Certify (`certify`)

1. Ejecutar compliance-check internamente
2. Verificar que TODOS los controles ≥ 80%
3. Si alguno < 80%:
   - Mostrar controles fallidos
   - Sugerir remediation plan
   - NO certificar
4. Si todos ≥ 80%:
   - Generar certificación:  `compliance-cert-YYYYMM.pdf`
   - Crear entrada en decision-registry
   - Guardar en `output/governance/certs/`
5. Output: certificación o lista de requierements

## Errores

| Error | Acción |
|---|---|
| Audit trail no encontrado | Crear `.audit-trail/actions.jsonl` vacío |
| Control sin evidencia | Marcar como gap; no bloquear certificación si ≥ 80% |
| Decision registry corrupto | Validar YAML; mostrar errores |
| Score < 80% en un control | Mostrar remediation plan; no certificar |

## Seguridad

- NUNCA exponér audit trail en reports públicos
- Certificación puede ser compartida (solo contiene scores, no detalles)
- Decision registry puede ser compartida (referencias a evidencia, no datos)
- Respect user privacy: después 4 años, anonimizar user field en audit trail
