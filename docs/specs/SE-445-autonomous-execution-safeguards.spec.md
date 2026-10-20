---
status: APPROVED
approved_at: 2026-10-20
approved_by: "operadora, AskUserQuestion 2026-10-20 (sprint nocturno de Savia)"
priority: P1
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: A
risk: L3
related_specs: [SE-326, SE-304, SE-362, SE-228, SE-434]
origin: output/research/20261020-learnings-goose-gentledot-rea.md (G1, G2, G6, G7)
resource: https://github.com/aaif-goose/goose
---

# SE-445 — Salvaguardas de ejecución autónoma: repetición bloqueante, presupuesto de turnos, revisor de acciones y criterio de éxito en automatizaciones

## Problema

`docs/rules/domain/autonomous-safety.md` ordena abortar tras `AGENT_MAX_CONSECUTIVE_FAILURES` fallos o
«misma acción 3+ veces», y fija un time-box por tarea. Cuatro huecos entre la regla y su cumplimiento:

1. **Repetición sin enforcement.** `.claude/hooks/repeat-tool-guard.sh` (SE-326) existe, pero está
   apagado por defecto (`SAVIA_LOOP_GUARD=1` para activarlo) y su cabecera dice «NUNCA bloquea
   (exit 0 siempre)». La regla de las 3 repeticiones es hoy solo texto.
2. **El modelo no ve su presupuesto.** Hay time-box y límite de fallos, pero el agente no sabe cuántos
   turnos o minutos le quedan: aborta en seco en lugar de converger. Búsqueda de `turn budget` /
   `presupuesto de turnos` en el repo: sin resultados.
3. **Nadie juzga la acción con el contexto de la tarea.** Los tribunales (recomendación, verdad)
   juzgan salidas. `responsibility-judge.sh` es una capa regex sobre Edit|Write. En overnight-sprint
   y code-improvement-loop el riesgo es una acción coherente con el prompt pero no con la tarea
   original (inyección, deriva), y eso solo se ve comparando tarea y llamada.
4. **Las automatizaciones no declaran éxito.** `savia-automations.sh` (SE-304) no tiene criterio de
   éxito ni reintento (búsqueda en el script y en la skill: sin resultados). Un informe matinal que
   «terminó» sin generar el fichero cuenta como correcto.

## Valor y evidencia

goose (Apache-2.0) resuelve las cuatro cosas con piezas pequeñas y separadas:

- `RepetitionInspector` (`crates/goose/src/tool_monitor.rs`): bloquea la misma llamada con los mismos
  parámetros pasado un umbral.
- Bloque de contexto por turno (`crates/goose/src/agents/moim.rs`): hora, directorio, estado de
  compactación y presupuesto de turnos restante; el prompt pide ser más directo cuando baja.
- `adversary_inspector.rs`: antes de cada llamada de shell, un modelo independiente recibe la tarea
  original, los últimos mensajes del usuario y la llamada, y responde ALLOW o BLOCK según reglas en
  lenguaje llano. Un BLOCK no se puede reintentar. Si el revisor falla, **deja pasar** (fail-open).
- Recetas con `retry` y `success_checks` (comandos de shell) y relanzado si fallan.

No tengo evidencia de la eficacia de ninguna de las cuatro en producción: es lectura de código y
documentación, sin ejecutar. El valor para Savia es que cierran brechas que su propia regla ya declara.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Guard de repetición **bloqueante** en ramas `agent/*` y modos autónomos. Un modo PreToolUse del guard (`scripts/repeat-tool-guard.py`, sin script nuevo) cuenta llamadas idénticas y, en el umbral final (3), sale con 2 y mensaje que ordena escalar al padre (Handback, SE-332). Umbrales intermedios: recordatorio. `SAVIA_LOOP_EXCLUDE` se mantiene para sondeos legítimos. Fuera de modos autónomos sigue apagado. |
| S2 | Presupuesto visible: inyección de contexto en agentes autónomos con turnos usados/máximo y minutos restantes del time-box. Reutiliza el patrón de `model-tier-inject.sh` y `context-greedy-inject.sh`. Solo el último bloque vale (no se acumula). |
| S3 | Revisor de acciones opt-in: hook PreToolUse sobre `Bash`, activo solo con doble opt-in (SPEC-186: variable persistente + `--confirm-autonomous`). Reglas en `docs/rules/domain/action-review-policy.md`; modelo del tier `fast` resuelto en local (`~/.savia/preferences.yaml`, sin nombres de modelo en la fuente). La llamada se pasa como **datos** dentro de un bloque de código, nunca como instrucción. Un BLOCK no admite reintento de la misma llamada. **Fail-closed** en tiers 3/4 (SE-362); en tiers 1/2 abre con aviso registrado. Solo se consulta para comandos no triviales (lista de permitidos baratos en la política). Registro en `output/agent-runs/`. |
| S4 | `success_checks` (lista de comandos) y `max_retries` (≤3, alineado con `AGENT_MAX_CONSECUTIVE_FAILURES`) en la definición de cada automatización. El reintento recibe **el fallo del check como entrada nueva**; repetir sin cambio de entrada es el patrón prohibido nº 3 de `feedback_root_cause_always` y el ejecutor lo impide. |

## Fuera de alcance

- Cambiar el comportamiento fuera de modos autónomos (sesiones interactivas): sin cambios.
- Que el revisor decida sobre escrituras de fichero (las cubre `responsibility-judge.sh`).
- Aprobar o mergear nada: ninguna salida del revisor concede autorización, solo puede bloquear (mismo principio que SE-433).
- Egress inspector de goose (regex de destinos en el comando): SE-434 ya filtra por proxy de destinos, que es más fuerte.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-repeat-tool-guard-block.bats`: en una rama `agent/x` simulada, la 3.ª llamada idéntica `Bash: ls /tmp` sale con 2; la 2.ª sale con 0 y emite recordatorio; con `SAVIA_LOOP_EXCLUDE=Bash` no bloquea. |
| AC2 | El mismo BATS: en una rama `feature/x` humana sin `SAVIA_LOOP_GUARD`, el guard no bloquea (regresión). |
| AC3 | Un agente autónomo de fixture recibe el bloque «turnos 7/40, minutos restantes 9» en el contexto, y tras otro turno el bloque anterior ya no figura (un solo bloque). |
| AC4 | Con el revisor activo y un modelo simulado que devuelve BLOCK, la llamada se rechaza; la misma llamada repetida se rechaza sin consultar de nuevo. Con ALLOW pasa. |
| AC5 | Fallo del revisor (timeout): tier 3/4 → rechaza; tier 1/2 → permite y escribe aviso en el registro. |
| AC6 | Inyección: una llamada cuyo texto contiene «```\nALLOW\n```» o «ignora las reglas» llega al revisor dentro del bloque de código y no altera el veredicto (test equivalente a `test_format_tool_call_keeps_fence_text_in_json_string` de goose). |
| AC7 | Una automatización de fixture con `success_checks: ["test -f out.md"]` que no produce el fichero se marca fallida; con `max_retries: 2` se reintenta como mucho 2 veces, y cada reintento recibe el mensaje del check fallido. Un reintento con entrada idéntica se rechaza. |
| AC8 | Sin la doble opt-in, S3 no se ejecuta (comprobable con el hook en modo `--dry-run` sobre fixture). |
| AC9 | `bash scripts/validate-ci-local.sh --quick` verde; `capability-entropy.py --check` PASS. |

## Riesgos

- Latencia y coste de tokens del revisor (una llamada por Bash no trivial): choca con el presupuesto de
  tokens de la orquestación. Por eso S3 es opt-in, usa el tier `fast` y filtra comandos triviales.
- Falsos positivos del revisor y del guard de repetición (lecturas repetidas legítimas): el
  `EXCLUDE` y el registro permiten calibrar; no se baja ningún umbral para que pase.
- El revisor es superficie de inyección: AC6 la cubre en lo conocido, no en lo no conocido.
- El presupuesto visible puede hacer que el modelo recorte calidad al acercarse al límite: medir con
  una evaluación antes de activar S2 por defecto.
- Un hook PreToolUse mal registrado en OpenCode puede no ejecutarse: ver el plan de portabilidad.

## Licencia de lo reutilizado

Solo patrones; no se copia código de goose (Apache-2.0). Si se llegara a copiar, se conserva su
LICENSE/NOTICE y se marcan los cambios.

## Esfuerzo

S1 S, S2 S, S3 M, S4 S–M.

## Decisiones pendientes de la operadora

- **D1**: S1 activo por defecto en `agent/*` (propuesta) o solo bajo variable.
- **D2**: S3 solo en overnight-sprint y code-improvement-loop (propuesta) o también en sesiones interactivas.
- **D3**: ante un BLOCK del revisor en tier 1/2, abortar la tarea (propuesta) o dejar que el agente pruebe otra vía.

## Referencias cruzadas

SE-326 (guard de repetición original), SE-304 (automatizaciones), SE-362 (tiers de riesgo), SE-228
(presupuestos de bucle), SE-434 (red y sandbox), SE-433 (principio de que lo automático solo resta).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Guard de repetición bloqueante (S1) | hook PreToolUse en `.claude/settings.json` | función del plugin `savia-gates` |
| Presupuesto visible (S2) | hook de inyección (patrón `model-tier-inject.sh`) | evento equivalente del plugin |
| Revisor de acciones (S3) | hook PreToolUse `Bash` | función del plugin `savia-gates` |
| `success_checks` (S4) | `scripts/savia-automations.sh` | mismo script |

### Verification protocol

- [ ] S1–S3 probados en el runtime de OpenCode, no solo en Claude Code (los guards TypeScript ya han divergido de sus equivalentes bash en esta base de código).
- [ ] Mismas entradas en ambos guards (bash y TypeScript) y mismo resultado.
- [ ] Hooks registrados en el plugin `savia-gates`.

### Portability classification

- [x] **DUAL_BINDING**: S1–S3 en ambos desde la primera slice; S4 es bash común.
