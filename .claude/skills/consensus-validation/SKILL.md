---
layer: peripheral
name: consensus-validation
description: Usar cuando una decisión técnica o recomendación necesita validación por panel de jueces.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: consensus-orchestrator
  savia.maturity: stable
  savia.category: governance
  savia.context: fork
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Panel de 4 jueces: reflection, code-review, business, performance. Cada juez evalua independientemente. Score ponderado 0-1.0. Veto rule: security/GDPR finding anula score. Output: JSON."
  savia.tags: "consensus, validation, multi-judge, quality"
---

## Subagent Scope Guard

> If you were dispatched as a subagent to execute a specific delegated task,
> **skip this skill's full orchestration workflow**. Execute only the assigned
> task, report result (DONE / DONE_WITH_CONCERNS / BLOCKED), and return.
> This guard prevents runaway skill activation in nested agent contexts.

# Skill: Consensus Validation

> Lanza 4 jueces especializados. Cada uno evalúa independientemente.
> Output: JSON estructurado con verdicts normalizados, score ponderado, dissents.
> El 4º juez (performance) usa `performance-audit` skill para detectar hotspots y anti-patterns.

**Referencia:** @docs/rules/domain/consensus-protocol.md

---

## Decision Checklist

Before invoking consensus, answer sequentially:

1. Was the code-reviewer verdict REJECTED? -> If YES: consensus is mandatory
2. Does the change involve auth, payments, PII, or compliance? -> If YES: consensus is mandatory
3. Is the spec marked ambiguous: true? -> If YES: consensus is mandatory
4. Is this a simple CRUD or cosmetic UI change? -> If YES: consensus unnecessary, standard review suffices
5. Is the risk score < 26 (Low tier)? -> If YES: consensus unnecessary

### Abort Conditions
- 2+ judges timeout -> CONDITIONAL verdict (insufficient data)
- Security veto by any judge -> auto-REJECT regardless of score

---

## 8-Step Protocol

### 1. Validar Input
```
type: spec | pr | decision
ref: file_path or PR_number
```

### 2. Formatear por Juez
- **reflection-validator:** Suposiciones, cadena causal, brechas de lógica
- **code-reviewer:** Código, diff, reglas SOLID, seguridad
- **business-analyst:** Reglas negocio, criterios aceptación, impacto
- **performance-auditor:** N+1 queries, async anti-patterns, complexity hotspots, bundle size

### 3-5. Invocar 4 Jueces en Paralelo (via dag-scheduling)
Dispatch via `dag-scheduling` skill — all 4 judges are independent (no deps), run as single parallel cohort.
Timeout: 40s por juez (120s total). Cada juez devuelve: verdict + reasoning + confidence (0.0–1.0)

### 6. Normalizar Verdicts a 0/0.5/1.0

| Judge | Verdict → Score |
|---|---|
| Reflection | VALIDATED→1.0 / CORRECTED→0.5 / REQUIRES_RETHINKING→0.0 |
| Code-review | APROBADO→1.0 / CAMBIOS_MENORES→0.5 / RECHAZADO→0.0 |
| Business | VÁLIDO→1.0 / INCOMPLETO→0.5 / INVÁLIDO→0.0 |
| Performance | OPTIMAL→1.0 / DEGRADED→0.5 / REGRESSION→0.0 |

### 7. Veto Check
```
if (code_verdict == RECHAZADO) AND (security|gdpr|compliance in reasoning):
  final_verdict = REJECTED; return early
if (perf_verdict == REGRESSION) AND (severity == CRITICAL):
  final_verdict = REJECTED; return early
```

### 8. Calcular Score Ponderado
```
score = (reflection × 0.3) + (code × 0.3) + (business × 0.2) + (performance × 0.2)

if score >= 0.75: verdict = APPROVED
elif score >= 0.50: verdict = CONDITIONAL
else: verdict = REJECTED
```

### 8.5. Detectar Dissents
```
avg = (reflection + code + business + performance) / 4
for judge in [reflection, code, business, performance]:
  if abs(judge_score - avg) > 0.5:
    dissents.append(judge)
```

If dissents and verdict == APPROVED → downgrade to CONDITIONAL

### 9. Generar Output JSON
```json
{
  "input": {type, ref, timestamp},
  "judges": [
    {name, verdict, score, reasoning, timeout, elapsed_ms}
  ],
  "veto": {triggered, reason},
  "summary": {
    "weighted_score": 0.62,
    "final_verdict": "CONDITIONAL",
    "dissents": ["business-analyst: ..."],
    "recommended_action": "corrections_required"
  }
}
```

Escribir a: `output/consensus/YYYYMMDD-HHmmss-{type}-{ref}.json`

## Dissent Rules

**Triggered si:** `abs(judge_score - promedio) > 0.5`

**Efecto:**
- dissents + APPROVED → CONDITIONAL
- dissents + CONDITIONAL → CONDITIONAL
- dissents + REJECTED → REJECTED

**Output:** listar dissents con razonamiento

## Error Handling & Timeline

**Errors:**
- Judge timeout: usar respuesta parcial (⚠️)
- 2+ timeouts: CONDITIONAL
- Veto triggered: REJECTED (final)

**SLA:** 120s máximo

## Integration & Antipatterns

**SDD:** opt-in after spec-writer | **PR:** mandatory if rejected | **ADR:** opt-in | **Audit:** `output/consensus/`
**NUNCA:** override veto, modificar verdicts post-facto, saltarse jueces
