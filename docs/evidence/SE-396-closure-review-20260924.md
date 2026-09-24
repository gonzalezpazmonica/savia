# SE-396 — revisión de cierre (2026-09-24)

**Estado: `IMPLEMENTING`; no graduar aún.** El mapa siguiente identifica
regresiones y evidencia local. Una ruta existente no demuestra por sí sola
que el criterio esté cumplido. Los PRs #1112–#1135 están integrados; falta
revisión humana del cumplimiento y de la evidencia operacional.

| Criterio | Evidencia revisable | Valoración |
|---|---|---|
| H01, reserva antes de ejecutar y efecto ambiguo | `tests/dual-cli/test_runtime.py` (replay, concurrencia, SIGKILL, deadline) | Regresión local: pasa |
| H02, referencias y autoridad previa al executor | `tests/dual-cli/test_runtime.py` (refs, elevación, policy/preflight) | Regresión local: pasa |
| H03, observación confiable y preflight estricto | `tests/dual-cli/test_harness_contracts.py`, `tests/dual-cli/test_config.py` | Controles negativos locales: pasan |
| H04, probe sintético sin graduación L2 | `tests/dual-cli/test_doctor_integrity.py`, doctor real descrito abajo | Controles negativos y sandbox nativo: pasan; faltan canaries de sesión real |
| H05, recibo inmutable y correlacionado | `tests/dual-cli/test_evidence_integrity.py`, `tests/dual-cli/test_harness_contracts.py` | Regresión local: pasa |
| H06, input inválido y extensiones | `tests/dual-cli/test_evidence_integrity.py`, `tests/dual-cli/test_harness_contracts.py` | Regresión local: pasa |
| H07, paridad y bloqueo de hooks | `scripts/opencode-plugin/savia-gates/__tests__/http-gate.test.ts` | Existe suite dirigida; no se ha repetido en esta revisión |
| H08, closure del manifest | `tests/dual-cli/test_config.py` | Regresión local: pasa |
| H09, sustitución Codex/OpenCode | `tests/dual-cli/test_bridge_cli_adapters.py`, `tests/dual-cli/test_bridge_cli_injection.py`, `docs/evidence/SE-396-a01c-operational-receipts.json` | Tests locales: pasan; recibo operacional requiere validación humana de procedencia |
| H10, dominios independientes | `tests/dual-cli/test_domain_packs.py`, `tests/dual-cli/test_runtime.py` | Regresión local: pasa |
| H11, integridad de planificación | `tests/test-planning-transition.bats`, `tests/test-roadmap-validate.bats` | 18/18 pasan; el estado permanece `IMPLEMENTING` |
| H12, aislamiento de cache federada | `projects/savia-vaults/tests/unit/federation/cache.test.ts`, `projects/savia-vaults/tests/unit/federation/search.test.ts` | Existen regresiones de principal/policy/revisión/provenance; no se han repetido en esta revisión |

## Verificación de esta revisión

- `python3 -m unittest discover -s tests/dual-cli -p 'test_*.py' -q`:
  **127/127** correctos.
- `bats tests/test-planning-transition.bats tests/test-roadmap-validate.bats`:
  **18/18** correctos.
- `bats tests/bats/test-contract-pin.bats`: **20/20** correctos tras
  actualizar el pin `settings-hooks` a v2. El cambio proviene del commit
  SE-371 de hooks de higiene de caché; v1 queda en modo compat sin autoridad.
- `bash scripts/roadmap.sh validate`: correcto.
- `bash scripts/planning-transition.sh check SE-396`: `NOT_READY` porque
  aún no existe `completion` con el mapa de aceptación final.
- `codex_profile.py probe` con Codex CLI 0.156.1: en el sandbox exterior el
  sandbox anidado no arrancó. Repetido con permiso fuera del sandbox exterior,
  usando el sandbox nativo de Codex y sólo fixtures temporales: autenticación,
  política, escritura de control y bloqueo L4 verdaderos. El doctor devolvió
  `DEGRADED_SAFE`, `max_verified_risk=null`, `passed=false` y
  `REAL_SESSION_CANARIES_MISSING`. No se elevó autoridad ni se configuró perfil.

## Lagunas de cierre

1. H04: el doctor real prueba controles del sandbox nativo, pero no una sesión
   de ejecución completa. Adjuntar canaries positivos y negativos de la sesión
   efectiva antes de cualquier claim L2; el resultado actual sigue degradado.
2. H09: el JSON de A01c declara resultados `VERIFIED`; su test comprueba
   estructura y minimización de datos, pero no verifica independientemente
   el origen de los efectos. Revisar el recibo operacional y su método de
   captura antes de aceptarlo como evidencia de sustitución real.
3. Repetir la suite TypeScript de H07 y la de SaviaVaults H12 en entorno con
   dependencias instaladas. La suite general anterior agotó 300 s; no hay
   baseline global verde demostrado en esta revisión.
4. Una vez resueltas estas lagunas, registrar `completion.merge_pr=1135` y
   `completion.acceptance_evidence` en `planning-state.json`; el chequeo debe
   devolver `NEEDS_HUMAN_REVIEW`. Sólo una revisión humana aprobada puede
   decidir la graduación final.
