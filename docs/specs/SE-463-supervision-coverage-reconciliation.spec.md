---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L2
related_specs: [SE-402, SE-445, SE-453, SE-434]
origin: investigación de arquitectura agéntica 2026-09-25 a 2026-10-23 (entradas 29 y 32)
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-463 — Cobertura de supervisión: reconciliar las llamadas de herramienta con lo que vieron los guards y fallar cerrado al perderla

## Problema

Los guards de Savia (hooks PreToolUse en Claude Code, `savia-gates` en OpenCode) solo controlan lo que
el arnés les enseña. Si un hook no se ejecuta (configuración que no lo registra, `disableAllHooks`,
un frontend o modo que no los carga, un fallo de arranque), la sesión sigue y nadie lo sabe. Medido
sobre `main` (0dd2ea30b):

- Ningún script ni hook compara las llamadas de herramienta que hizo una sesión con las decisiones
  que registraron los guards. Búsqueda de `tool_use_id` en `.claude/hooks/` y `scripts/`: cero
  coincidencias.
- La única reconciliación de efectos contra registro es la del ledger de ediciones (SE-402,
  `scripts/edit_ledger_verify.py`): ficheros cambiados en la rama que ninguna Edit/Write atribuye.
  Cubre ficheros, no órdenes, red ni git remoto, y en `scripts/pr-plan-gates.sh` (G19) es solo aviso.
- Yema lo declara como límite en `docs/gobernanza.md` de su repositorio: «La puerta solo ve lo que el
  arnés le enseña. Si el arnés no pasa una herramienta por el hook, no la controla».
- La línea de investigación del metaharness desactiva los hooks a propósito en una de sus variantes
  (`disableAllHooks`) para medir sobrecoste: la situación es real y reproducible.

## Valor y evidencia

- Salt Security, «State of Agentic AI and API Security 2H 2026» (13-oct-2026): encuesta a más de 380
  profesionales; solo el 12,5 % puede trazar de forma consistente la ruta completa de un agente y solo
  el 17,5 % puede detener automáticamente uno que se comporta de forma inesperada. Verificado; es
  encuesta de proveedor, no muestreo probabilístico. Se usa como contexto, no como umbral.
- La entrada 32 del consolidado (red-teaming de la monitorización interna de agentes de un
  laboratorio) **no se ha podido verificar** con ese título y fecha; no se usa como evidencia.
- Evidencia propia, la que manda: la ausencia medida arriba.

## Alcance

| Slice | Entrega |
|---|---|
| S0 | Medir qué identifica una llamada en cada frontend: si la entrada de PreToolUse trae un identificador de llamada y si aparece en el registro de la sesión. Resultado en el informe del slice. Si no hay identificador común, S1 usa (orden, herramienta, huella de la entrada) y lo declara. |
| S1 | Latido de guard: un registro de una línea por llamada vista (`~/.savia/supervision/<session>.jsonl`: id, herramienta, decisión), escrito por un hook ligero que corre el primero; en OpenCode, por `savia-gates`. |
| S2 | `scripts/supervision-reconcile.sh <session>` compara las llamadas del registro de la sesión del frontend con el latido. Resultado con los tres estados de SE-453 y mapeo declarado aquí (script nuevo): `clean` = salida 0 (todas vistas), `findings` = salida 1 (llamadas sin latido, listadas), `unknown` = salida 2 (no se puede leer alguno de los dos registros). |
| S3 | Fail-closed en ejecución autónoma: el cierre de los workers y `pr-plan` en ramas `agent/*` ejecutan la reconciliación; `findings` o `unknown` → no se abre la PR y la marca de fin dice «cobertura de supervisión perdida». En sesiones interactivas, solo aviso. |

## Fuera de alcance

- Un monitor independiente del arnés (proceso aparte que observe el sistema): es la frontera de SE-434.
- Detener la sesión en tiempo real al detectar el hueco: aquí se detecta al cerrar.
- Promover G19 (SE-402) a bloqueante: decisión aparte.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | pytest con fixtures de registro de sesión y latido idénticos: `supervision-reconcile.sh` sale 0 (`clean`). |
| AC2 | Negativo: el fixture de latido omite 2 de 10 llamadas → sale 1 (`findings`) y lista las 2. |
| AC3 | Negativo: latido ausente o ilegible → sale 2 (`unknown`), nunca 0. |
| AC4 | Negativo: en una rama `agent/*` con resultado `findings`, el cierre del worker no invoca `gh pr create` (espía) y escribe el motivo en la marca de fin. |
| AC5 | En una sesión interactiva con `findings`, solo imprime aviso y sale 0 del paso de PR. |
| AC6 | Prueba de extremo a extremo (S0 permitiendo): una sesión `claude -p` corta con hooks y otra con `disableAllHooks` dan `clean` y `findings` respectivamente. |

## Riesgos

- Coste por llamada del latido: una escritura de una línea. Se mide en S1 contra `test-hook-latency-audit.bats`.
- Formato del registro de sesión del frontend cambia entre versiones: el lector falla a `unknown`, que bloquea en autónomo. Preferible a un falso `clean`.
- Un agente que escribe su propio latido: el directorio de latidos se añade a las rutas protegidas de los guards de escritura.

## Decisiones de la operadora

- **D1**: ¿bloquear en autónomo desde el primer día o empezar en aviso una semana? (propuesta: aviso una semana con medición, luego bloqueo).
- **D2**: ¿reconciliar también subagentes? (propuesta: sí si S0 muestra que sus llamadas pasan por los mismos hooks).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Latido (S1) | hook PreToolUse ligero | registro desde `savia-gates` |
| Reconciliación (S2, S3) | script, lee el registro de sesión de Claude Code | el mismo script con lector del registro de OpenCode |

### Verification protocol

- [ ] AC1 a AC5 corren con fixtures, sin frontend.
- [ ] AC6 se ejecuta en los dos frontends o se declara no ejecutado en uno con el motivo.

### Portability classification

- [x] **DUAL_BINDING**: el latido existe en los dos frontends; la reconciliación es un script común con un lector por frontend.
