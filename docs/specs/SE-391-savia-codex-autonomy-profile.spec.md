---
status: IMPLEMENTING
priority: P1
developer_type: agent-single
extends: SE-388
created: 2026-09-07
---
# SE-391 — Savia Codex Autonomy Profile

Implementar `SAVIA_CODEX_PROFILE=autonomous-l2`: ejecución autónoma L0-L2
dentro del scope, con efectos externos denegados por defecto. L3 requiere
criterio humano; L4 queda bloqueado o se redirige a humano. Capacidad técnica
del frontend no concede autoridad. El agente no puede elevar su propio techo.

La proyección Codex se deriva de la policy Savia, detecta versión y capacidades
reales, preserva configuración personal, verifica sandbox y enforcement antes
de escribir, emite receipts metadata-only y revierte ante fallo. Nunca usa
bypass global, auto-push, auto-merge, auto-deploy ni red abierta por defecto.

## Acceptance criteria

1. Ciclo editar/test/corregir/lint/build L0-L2 sin aprobaciones mecánicas.
2. Push, merge, deploy, secretos, expansión de scope y decisiones nuevas paran.
3. Configuración version-aware, idempotente, reversible y no destructiva.
4. Doctor informa estado efectivo mediante probes, no sólo configuración.
5. Canaries C1-C14 y prompts adversariales no elevan autoridad.
6. Receipts demuestran ejecución delegada y criterio humano.
7. Cambios relevantes de versión invalidan evidencia previa.
8. SE-388 permanece IMPLEMENTING; Codex queda DEGRADED_SAFE, techo L2.

## Implementation plan

- Policy compartida: `scripts/dual-cli/autonomy.py`.
- Proyección/probes: `scripts/dual-cli/codex_profile.py` y
  `scripts/configure-codex.sh`.
- Doctor: `scripts/dual-cli/autonomy_doctor.py`, integrado en
  `scripts/workspace-doctor.sh --codex-autonomy`.
- Canaries: `tests/dual-cli/test_autonomy.py`, adversariales incluidos.
- Evidence: paquete local reproducible, sin secretos ni credenciales.

## Estado comprobado

Codex 0.153.4 está autenticado. El sandbox y la escritura del workspace pasan
tras autorizar un perfil AppArmor específico para su helper `bwrap`. La
proyección usa permission profiles nativos: `:workspace` para L0-L2 y
filesystem `deny` para `~/.codex/auth.json`. La matriz real deniega siete vías
de lectura y el ciclo edit/test/fail/fix/test/lint-build termina sin aprobaciones
mecánicas. El estado permanece `IMPLEMENTING`, `DEGRADED_SAFE`, techo L2;
L3/L4 siguen `BLOCKED_OR_HUMAN_REROUTE` y no se gradúan por esta spec.
