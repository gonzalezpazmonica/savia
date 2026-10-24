---
id: SE-400-F1
parent: SE-400
status: READY_FOR_HUMAN_REVIEW
created: 2026-10-24
evidence_type: deterministic-repository-inventory
model_invocations: 0
---

# SE-400 F1 — Normalización Resource/Capability (+ F2 parcial)

## Qué entrega

| Pieza | Ruta |
|---|---|
| Contrato base versionado (1.0.0) | `config/ablation-contract.json` |
| Inventario de solo lectura | `scripts/ablation_inventory.py {generate,check,summary}` |
| Grafo de consumidores estáticos (F2 parcial) | `scripts/ablation_consumers.py` |
| Tests | `tests/test_ablation_inventory.py`, `tests/test-se400-ablation-f1.bats` |
| Informe regenerable | `output/ablation/f1-inventory.{json,md}` (no versionado) |

Decisión humana F0 n.º 1 resuelta con criterio conservador: F1 **no amplía el
schema del SAM**. Es una capa superpuesta que apunta al nodo `CAPABILITY` del
SAM cuando existe; no hay otro grafo ni otra fuente de verdad.

## Reglas que el código impone

- El baseline es el contrato: el validador rechaza `model`, `provider`,
  `frontend` o `baseline_model` en cualquier punto del baseline, exige versión
  semver y los floors no compensables `authority_effect_correctness` y
  `security_floors`.
- Clase taxonómica solo con autoridad verificable: SAM (`Capability`),
  settings (`Control`), registry de packs (`DomainPack`), generator declarado
  y versionado (`GeneratedView`), symlink (`Projection`), ubicación `scripts/`
  (`Script`). Sin autoridad: `UNKNOWN`, con motivo y, aparte, hipótesis no
  autoritativas.
- `CORE_*`, `MERGE_CANDIDATE`, `REDUNDANT_CANDIDATE` y `DEAD` exigen receipt
  de ablación; los dos últimos, además, Human Gate. F1 no tiene receipts, así
  que no puede emitirlos. `UNKNOWN` nunca lleva acción de retirada.
- Frescura por contenido (blobs git + contrato + revisión SAM + hash SCM); el
  HEAD es informativo, igual que en el SAM tras #1301.

## Resultado medido

Árbol `201c94102` (rama, sobre main `bc4934311`). 2.657 registros.

| Kind | Física | Indexada en SAM | Sin consumidor estático | Solo consumidores test |
|---|---:|---:|---:|---:|
| command | 580 | 295 | 53 | 4 |
| skill | 137 | 137 | 0 | 0 |
| agent | 165 | 90 | 83 | 6 |
| hook | 126 | 0 | 0 | 1 |
| script | 1.286 | 926 | 255 | 197 |
| rule | 342 | 0 | 75 | 11 |
| generated_view | 10 | 0 | — | — |
| frontend_link | 9 | 0 | — | — |
| pack | 2 | 0 | — | — |

| Clase | Registros | | Essentiality | Registros |
|---|---:|---|---|---:|
| Script | 1.286 | | UNKNOWN | 2.636 |
| UNKNOWN | 706 | | RUNTIME_PROJECTION | 9 |
| Capability | 522 | | GENERATED_VIEW | 10 |
| Control | 122 | | DOMAIN_PACK | 2 |
| GeneratedView / Projection / DomainPack | 10 / 9 / 2 | | CORE_*, MERGE, REDUNDANT, DEAD | 0 |

Hallazgos deterministas:

1. **926 de las 1.448 «capabilities» del SCM son scripts.** `RESOURCE !=
   CAPABILITY` queda cuantificado: el SAM solo respalda 522 capabilities de
   cara al usuario (295 commands, 137 skills, 90 agents).
2. **75/75 agents de `.claude/agents` tienen gemelo en `.opencode/agents`**
   (`MIRROR_OF`). Candidatos a proyección o compatibilidad; no se tocan.
3. **Los 9 symlinks de frontend** (`.opencode/{commands,skills,hooks,...}`,
   `.agents/skills`) son las únicas proyecciones de runtime con autoridad hoy.
4. **122 hooks registrados, 4 no registrados** (coincide con F0).
5. **466 recursos sin ninguna referencia literal**, 129 de ellos scripts
   indexados en el SAM. Ejemplo: `docs/rules/domain/agent-jwt-mint.md` no tiene
   consumidores; los consumidores apuntan a
   `docs/rules/domain/savia-enterprise/agent-jwt-mint.md`, un fichero distinto
   con el mismo nombre. Es entrada para el experimento A0, no para retirar.

## Limitaciones

- Consumidor = referencia literal por ruta, `hooks/<x>.sh`, directorio de skill
  o `/<comando>`. Agents y skills citados solo por nombre no cuentan; por eso
  83 agents salen sin consumidor. No mide uso real ni invocaciones.
- Registro en settings no es invocación. Solo árbol versionado.
- F2 completo (grafos de dependencias, contratos y fallos) no está hecho.

## Acceptance Criteria

| AC | Estado | Verificación |
|---|---|---|
| AC01 baseline sin modelo | Cerrado para el inventario | `test_model_as_baseline_is_rejected`, `test_invalid_contract_aborts_generation` |
| AC02 contrato versionado | Cerrado | `contract_version` + `contract_sha256` en procedencia; `test_contract_must_be_versioned` |
| AC08 evidencia en HEAD | Cerrado para F1 | `check` → STALE si cambia el contenido; `test_check_detects_stale_report` |
| AC09 gates de retirada física | Cerrado en el schema | `test_dead_without_receipt/human_gate_*` |
| AC11/AC12 separación y fuentes de verdad | Cerrado (estático) | clase + origen por frontend + `MIRROR_OF` |
| AC13 essentiality en SAM | Parcial | campo presente; todo `UNKNOWN` sin ablación |
| AC34 UNKNOWN nunca delete | Cerrado | `test_unknown_never_carries_removal` |
| AC03–07, AC10, AC14–33, AC35–46 | Abiertos | requieren ablaciones A0–A6, panel de modelos o kernel candidato (F3+) |

## Siguiente

F2 restante: dependencias declaradas (`depends_on` vacío en SCM) y matriz
event→hook→failure, prerrequisito de A4. Después, preregistro del primer A0.
