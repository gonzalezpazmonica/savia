---
name: legal-compliance-checker
description: "Verifica procesos o documentos contra regulaciones ES (RGPD, LO 3/2018, ET, CCom). Produce gaps y plan de remediación."
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: professional-domain/legal
  savia.context: isolated
  savia.context_cost: medium
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Audita procesos o documentos contra regulaciones específicas. Identifica gaps de compliance, nivel de riesgo y acciones de remediación. Input: proceso/documento + regulaciones aplicables. Output: informe de gaps."
  savia.tags: "compliance, RGPD, ET, AEPD, legal, ES"
---

# legal-compliance-checker — Verificador de Compliance

## Cuándo usar esta skill

- Al implantar un nuevo proceso que trate datos personales (RGPD).
- Antes de lanzar un producto o servicio en España (LO 3/2018).
- Al revisar contratos laborales o procedimientos disciplinarios (ET).
- Para auditorías internas de cumplimiento normativo.
- Al recibir un requerimiento de la AEPD o inspección de trabajo.

## Inputs requeridos

| Campo | Descripción | Ejemplo |
|---|---|---|
| `objeto` | Proceso o documento a auditar | Procedimiento de videovigilancia |
| `regulaciones` | Normas aplicables a verificar | `RGPD`, `LO 3/2018`, `ET`, `CCom` |
| `contexto` | Sector / tamaño empresa / actividad | Empresa 50 trabajadores, sector salud |

## Outputs producidos

1. **Tabla de gaps por regulación** — artículo / obligación / estado (cumple/gap/N/A) / evidencia requerida
2. **Nivel de riesgo por gap** — ALTO (infracción muy grave) / MEDIO (grave) / BAJO (leve)
3. **Plan de remediación** — acciones ordenadas por urgencia con responsable y plazo estimado
4. **Alertas de AEPD** — gaps con más precedentes sancionadores identificados explícitamente

## Outputs excluidos

- Opinión jurídica vinculante sobre interpretación normativa
- Representación ante organismos reguladores
- Garantía de ausencia de infracción

## Disclaimer

Todo output incluye disclaimer legal completo. Ver `docs/rules/domain/professional-domain-disclaimer.md`.

## Relación con otras skills

- **Upstream**: `legal-contract-reviewer` (obligaciones identificadas en contratos)
- **Downstream**: `legal-document-drafter` (documentación de medidas correctoras)
