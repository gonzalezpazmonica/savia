---
name: governance-audit
description: Auditoría de cumplimiento de política de IA — acciones vs permitidas
developer_type: all
agent: task
context_cost: high
model_tier: heavy
tier: core
---

# /governance-audit

> 🦉 Auditar que las acciones de Savia cumplen la política de gobernanza.

Auditoría de cumplimiento basado en NIST AI RMF (Map, Measure) y AEPD (IA agéntica).

Carga la política, escanea el log de acciones, detecta incumplimientos y excepciones.
Incluye criterios AEPD para agentes autónomos: @.opencode/skills/regulatory-compliance/references/aepd-framework.md

---

## Flujo

1. **Paso 1** — Cargar `company/policies.md` (error si no existe)
2. **Paso 2** — Leer log de acciones (`.claude/agent-notes/action-log.jsonl` o similar)
3. **Paso 3** — Para cada acción, verificar:
   - ¿Clasificación de riesgo correcta?
   - ¿Tenía autorización?
   - ¿Se documentó?
4. **Paso 4** — Detectar violaciones y excepciones (aprobadas o no)
5. **Paso 5** — Presentar audit report con tendencias

---

## Verificaciones

### Conformidad
- ✅ Acción clasificada correctamente
- ✅ Aprobadores participaron
- ✅ Documentación completa

### Incumplimientos
- 🔴 Acción de CRÍTICO sin CTO
- 🔴 Acción clasificada como BAJO siendo ALTO
- 🔴 Acción sin documentación

### AEPD — IA Agéntica
- 🔴 Agente sin EIPD documentada
- 🔴 Sin base jurídica para tratamiento de datos
- 🟡 Scope guard ausente o desactivado
- 🟡 Falta protocolo notificación brechas 72h

### Excepciones
- 🟡 Acción permitida por excepción documentada
- 🟡 Escalation aprobado por CTO

---

## Output

Fichero: `output/audit-YYYYMMDD-gobernanza.md`

Secciones:
- Resumen ejecutivo (score cumplimiento 0-100%)
- Hallazgos por clasificación de riesgo
- Violaciones detectadas (prioritizadas)
- Excepciones (documentadas y aprobadas)
- Tendencias (últimos 30/60/90 días)
- Recomendaciones de mejora

**Integración**: Input para `/governance-report`, `/governance-certify` y `/aepd-compliance`.
