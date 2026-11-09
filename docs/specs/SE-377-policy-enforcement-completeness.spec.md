# SE-377 — Policy Enforcement Completeness: TEST + RECEIPT

**Estado:** SUPERSEDED — decisión de la operadora del 2026-11-09 por pregunta interactiva; absorbida por SE-453 y SE-454 (gate de bloqueo pendiente). Estado y aprobación anteriores: Mónica (operadora), 2026-09-05: "Apruebo todas, implementa, pr y merge"
**Prioridad:** P0 · **Developer Type:** agent-team · **Context Risk:** medium
**Origen:** auditoría externa §8 (PARTIALLY_ALREADY_SOLVED — depende de SE-374, mergeada hoy)

## 1. Motivación

SE-374 (PR #1080, 2026-09-05) ya audita POLICY→TRIGGER→ENFORCEMENT con 12 cruces RN (resultado inicial: P0=241, P1=6, P2=8 — 78/318 prohibiciones con pared determinista). El contrato completo del audit añade dos capas que SE-374 no cubre:

```
POLICY → TRIGGER → ENFORCEMENT → TEST → AUDIT RECEIPT
                                   ^^^^    ^^^^^^^^^^^^^
                                   faltan    faltan
```

## 2. Alcance

1. **Capa TEST**: todo hook/gate clasificado ENFORCEMENT en el inventario SE-374 debe tener ≥1 negative test (input que dispara el bloqueo → aserción exit≠0/block). Los 241 P0 del gap report pasan a priorizar qué normas merecen pared nueva, con el criterio L4/L3 de la propuesta.
2. **Capa RECEIPT**: todo bloqueo real emite receipt auditable (quién, qué, cuándo, qué regla) consumible por el pipeline SE-374 y por RCA.
3. **Registry de políticas**: extender inventory.json con `policy_id, severity, statement, trigger, enforcement, failure_mode, tests[], receipt, exceptions[]`.

### Clasificación de severidad (del audit §8.3)

- **L4**: enforcement determinista obligatorio + negative test obligatorio + fail-closed salvo excepción explícita.
- **L3**: enforcement O confirmación humana estructurada.
- **L0-L2**: advisory permitido según riesgo.

## 3. Principio arquitectónico

NO crear un hook por regla. Preferir gates compartidos, funciones reutilizables en `hooks/lib/`, manifests y checks centralizados. `guardrail-audit.sh` (SE-374) es el verificador, no se duplica.

## 4. Reglas de negocio

| # | Regla | Severidad |
|---|---|---|
| RN-01 | 100% enforcement L4 con negative test | P0 |
| RN-02 | Enforcement sin test → P1 en gap report | P1 |
| RN-03 | Ningún enforcement huérfano (sin policy_id) | P1 |
| RN-04 | Todo bloqueo emite receipt (muestreo verificable) | P1 |
| RN-05 | Excepciones solo con razón+owner+fecha+re-evaluación | P0 |
| RN-06 | La auditoría extendida sigue siendo read-only (RN-12 SE-374) | P0 abort |

## 5. Criterios de aceptación

- `guardrail-audit.sh` ampliado distingue norma / warning / confirmation / blocking enforcement / test coverage / receipt coverage.
- Cruce "enforcement sin negative test" visible en compliance-matrix.md.
- Fixtures de negative test para ≥10 enforcement L4 reales (block-force-push, block-credential-leak, push-pr gate, operator-grant...).
- Determinismo y runtime ≤60s preservados.

## 6. OpenCode Implementation Plan

### Clasificación
- **Tier:** 2 · **Agent-capable:** yes
- **Slices:** S1 capa TEST (negative tests ejecutables para ≥10 enforcement) · S2 capa RECEIPT (detección de emisión auditable) · S3 integración en guardrail-audit.sh (cruces ampliados)

## Referencias

- Auditoría externa §8 · SE-374 (`docs/specs/SPEC-SE-374-GUARDRAIL-PRINCIPLE-AUDIT.spec.md`, PR #1080) · audit receipts (Savia Enterprise)
