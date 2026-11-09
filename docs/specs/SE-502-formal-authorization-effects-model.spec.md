---
status: DEFERRED
priority: P1
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L2
related_specs: [SE-343, SE-362, SE-387, SE-433, SE-493, SE-494, SE-496, SE-498, SE-500]
resource: https://github.com/cursor/plugins/blob/main/pstack/skills/create-formal-verification-skill/SKILL.md
origin: "Informe de investigación sobre 115 números de la newsletter The Code (archivado en SaviaLabs, labs/research/20261103-the-code-oportunidades.md), propuesta 1. Adoptada por la orquestadora con autoridad delegada de la operadora. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
---

# SE-502 — Modelo formal de autorización y efectos

## Problema (verificado en origin/main 2acce7c37, 2026-11-03)

Savia decide efectos externos irreversibles (hoy, sobre todo `pr.merge`) a partir de varias piezas que se intercalan en el tiempo: un grant de la operadora con TTL y consumo único, una reserva de efecto, una llamada remota que puede quedar con resultado incierto, una revocación y un STOP. Cada pieza tiene sus tests, pero ninguno explora **todos los órdenes** en que dos ejecutores, un reloj y una revocación pueden intercalar esos pasos.

Ejemplo real del código actual, en `scripts/push-pr.sh`:

| Paso | Línea | Qué hace |
|---|---|---|
| comprobar grant | `push-pr.sh:237` (`grant_ok`) | `operator-grant.sh check --print-head` |
| reservar efecto | `push-pr.sh:274` | `f5-state.sh reserve pr.merge N \|\| exit 3` |
| volver a comprobar el grant | `push-pr.sh:279` | `grant_ok` otra vez, justo antes del efecto |
| efecto | `push-pr.sh:281` | `gh pr merge --match-head-commit <sha firmado>` |
| marcar enviado | `push-pr.sh:288` | `f5-state.sh mark_submitted` |
| consumir grant | `push-pr.sh:304` | `operator-grant.sh consume`; si falla, `revoke` |

Entre `:279` y `:281` queda una ventana en la que una revocación no se ve. Entre `:281` y `:304` el grant sigue vivo aunque el efecto ya ocurrió. SE-493 (PR #1455) documenta que un fallo ambiguo en `:281` invita a repetir (H3, H5). Nadie ha comprobado de forma sistemática qué otras combinaciones existen, ni si los diseños que vienen (SE-493, SE-496, SE-498) las cierran **juntos**.

## Discovery: qué ya cubre cada hueco (sección 12 del informe)

| Pieza | Dónde | Qué cubre | Qué no cubre |
|---|---|---|---|
| Effect Ledger | SE-493, PR #1455 (PROPOSED), `docs/specs/SE-493-effect-ledger-ambiguous-reconciliation.spec.md:95-118` (estados), `:121` (write-ahead), `:319` (AC-g) | Máquina de estados de un efecto: `PREPARED → DISPATCHED → SUCCEEDED/FAILED/NEEDS_REVIEW`, nada ambiguo devuelve «adelante», tests con contador de stub | La composición con grant, revocación y STOP. Sus tests prueban carreras concretas, no todos los órdenes. |
| Kernel de autoridad | SE-496 en main (PROPOSED), `docs/specs/SE-496-governed-operational-ontology-authority.spec.md:81-110` (contrato, techo de autoridad, revocación), `:128` (`evaluate` no consume), `:152-153` (`recheck`), batería R5 `:193-228` | Delegación con techo (mínimo entre contrato, agente y tier), `max_uses`, D04 «revocado entre evaluar y ejecutar», carrera de dos `recheck` con `max_uses: 1` | Prueba casos elegidos; no hay exploración exhaustiva ni composición con el ledger. |
| STOP global | SE-498, PR #1462 (PROPOSED), `docs/specs/SE-498-global-stop-cross-executor-revocation.spec.md:76-86` (época), `:135` (comprobación local antes de cada efecto) | Época monótona, acuses, revocación entre ejecutores | Si la comprobación de época y el `dispatch` del ledger son atómicos entre sí. |
| Trazas a regresiones | SE-494, PR #1453 (PROPOSED), `docs/specs/SE-494-trace-hermetic-regressions.spec.md:71-73` (esquema `savia.trace/v1`, 10 fallos congelados) | Contrato fail-to-pass, fixtures herméticas | Comparar trazas con un modelo de transiciones admitidas. |
| merge-sprint | SE-433, SE-500 (S1 en main); `tests/test-merge-sprint.bats:565` (dos `run` concurrentes) | Exclusión mutua de dos ejecuciones del sprint | Revocación y STOP intercalados con el merge. |
| Grants | SE-343, `scripts/operator-grant.sh:12,121` (consumo único), `:200` (ids gastados) | Uso único y libro de gastados | Orden relativo con la reserva F5 y el efecto. |
| Hashline edits | SE-149 | Ediciones concurrentes de ficheros | Nada de autorización ni efectos remotos: fuera de este modelo. |
| Herramientas | `grep -ri 'tla+\|apalache\|model.checking'` en todo el repo: sin resultados relevantes (solo el código de dominio «TLC» de telecomunicaciones en `scripts/fronema.py:30`). En la máquina de referencia no hay `java` ni `tlc`. | — | No existe ningún modelo formal ni herramienta instalada. |

**Recorte que hace el discovery.** Las garantías de cada pieza ya están especificadas en SE-493, SE-496 y SE-498. Esta spec **no** propone mecanismos nuevos, ni runtime, ni cambios de estados: solo un modelo que compone esas piezas y comprueba sus invariantes, y una vía para que cada contraejemplo se convierta en test del código real. El análisis de concurrencia de ficheros (SE-149) y la selección de CI quedan fuera.

## Qué decide esta spec

Un **modelo TLA+ mínimo y versionado** del ciclo de autorización y efecto, comprobado con un model checker sobre un espacio finito, con dos usos:

1. **Contra el código actual** (`push-pr.sh`, `operator-grant.sh`, `f5-state.sh`): encontrar órdenes que violan un invariante y convertir cada contraejemplo en un test hermético que falla hoy.
2. **Contra los diseños PROPOSED** (SE-493, SE-496, SE-498): comprobar, antes de implementarlos, que juntos cierran esos contraejemplos.

No es una prueba del software. Se prueban propiedades **del modelo** en un espacio acotado; la correspondencia con el código se contrasta con tests y, más adelante, con trazas reales (SE-494). Cualquier texto que diga «verificado formalmente» sin esta precisión es un defecto de la spec.

## Modelo

### Entidades y estados

| Entidad | Estados |
|---|---|
| `Intent` | `requested`, `authorized`, `withdrawn` |
| `Grant` | `issued`, `consumed`, `revoked`, `expired` (TTL discreto: un contador de ticks) |
| `Execution` | `idle`, `checking`, `reserved`, `executing`, `committed`, `ambiguous`, `reconciled`, `aborted` |
| `Effect` (remoto) | `absent`, `present` (el remoto es la autoridad, como en SE-493) |
| `Receipt` | `none`, `issued` |
| `STOP` | `running`, `paused`, `revoked(epoch)` |
| `Retry` | acción de un ejecutor sobre una `Execution` previa |
| `Rollback` | solo para efectos declarados reversibles; `pr.merge` no lo es, así que en Fase 1 el rollback es la ausencia de efecto, no su deshacer |

### Acciones

`Request`, `Issue`, `Check` (lee el grant), `Reserve`, `Recheck`, `Dispatch` (envía la llamada), `RemoteApply` (el remoto aplica o no, de forma no determinista), `Respond` (llega o se pierde la respuesta), `Consume`, `Revoke`, `Expire` (avance del reloj), `Stop`, `Crash` (un ejecutor muere en cualquier punto), `Retry`, `Reconcile` (sonda del remoto).

### Invariantes

| Id | Invariante |
|---|---|
| I1 | Ningún `Dispatch` ocurre con un grant `revoked` o `expired` en el instante del `Dispatch`, salvo que el modelo de esa variante declare explícitamente la ventana residual (ver I1-residual). |
| I1-residual | La ventana entre la última comprobación y el efecto está acotada a un solo paso atómico y está **nombrada** en el modelo; si aparece una ventana de más de un paso, es violación. |
| I2 | Ningún hijo tiene más autoridad que su padre: la autoridad efectiva de una delegación es ≤ la del principal (SE-496 R2). |
| I3 | Un `Receipt` solo se emite con `Effect = present` observado por sonda o respuesta con evidencia; una declaración de éxito sin evidencia no basta. |
| I4 | Desde `ambiguous` no hay segundo `Dispatch` del mismo efecto no idempotente sin un `Reconcile` previo que observe `absent`. |
| I5 | Tras `Stop`, ningún `Dispatch` nuevo; tras `Revoke`, ningún grant emitido en una época anterior autoriza un `Dispatch`. |
| I6 | Un grant de uso único autoriza a lo sumo un `Effect = present` (como mucho un efecto por grant, en cualquier intercalado). |
| L1 (vivacidad, opcional) | Con equidad débil, toda `Execution` en `ambiguous` llega a `reconciled` o queda señalada `NEEDS_REVIEW`; nunca se queda en un estado que devuelve «adelante». |

## Fases

### Fase 1 — Spike acotado (sin efectos)

- Modelo del **código actual**: `push-pr.sh` + `operator-grant.sh` + `f5-state.sh`, con dos ejecutores, un recurso (un PR), un grant, TTL de 2 ticks, `Crash` y `Revoke` en cualquier punto.
- Herramienta: TLC o Apalache, la que esté disponible. Ninguna se instala de forma global ni con privilegios: si no está, el script lo dice y sale BLOCKED.
- Script `scripts/formal-check.sh <modelo>` con resultado de una sola línea y exit estable:

| Exit | Resultado | Cuándo |
|---|---|---|
| 0 | `PASS` | El checker terminó, exploró el espacio completo y no hay violaciones |
| 1 | `FAIL` | Hay contraejemplo; se escribe en `output/formal/<modelo>/<fecha>-cex.json` |
| 3 | `UNKNOWN` | El checker no terminó (límite de tiempo o de estados) o la salida no se puede interpretar |
| 4 | `BLOCKED` | Falta la herramienta, falta la JVM o el modelo no existe |

  Ninguna otra combinación da 0. `PASS` exige que la salida del checker contenga su línea de fin de exploración y el número de estados distintos; si falta, es `UNKNOWN`.
- **Calibración obligatoria**: el modelo del código actual debe reproducir como contraejemplo el caso H3 que SE-493 ya documentó (fallo ambiguo en `push-pr.sh:281` y relanzamiento). Si no lo encuentra, el modelo es infiel y la fase no se cierra.
- Cada contraejemplo nuevo se traduce a un test BATS hermético contra los scripts reales con `gh` simulado por stub (contador de llamadas, como AC-g de SE-493): el test falla en el código actual. La corrección **no** forma parte de esta spec; va a la spec dueña de la pieza (SE-493, SE-496 o SE-498) o a una PR propia.

### Fase 2 — Diseños PROPOSED

- Modelo de SE-493 + SE-496 + SE-498 tal como están redactadas en sus PR. Mismos invariantes.
- Cada contraejemplo se devuelve como comentario a la PR de la spec afectada, con la traza mínima. No se reabren specs desde aquí.
- Cuando esos diseños se implementen, los tests de Fase 1 deben pasar a verde sin cambiar su aserción.

### Fase 3 — Refinamiento contra trazas reales

- A través de SE-494: un comprobador lee trazas `savia.trace/v1` de ejecuciones reales de merge y comprueba que cada transición observada es una transición admitida por el modelo. Una transición no admitida es un hallazgo (modelo incompleto o código fuera de contrato), nunca se descarta en silencio.
- Solo lectura. Depende de que SE-494 esté APPROVED e implementada; si no, la fase queda BLOCKED.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-1 | Existe `formal/authz-effects/` con el modelo del código actual y un fichero de configuración del espacio finito (2 ejecutores, 1 recurso, 1 grant, TTL 2). | positivo |
| AC-2 | El modelo enuncia I1–I6 y al menos cuatro están revisados por una persona (comentario en la PR con quién y qué invariante). | positivo |
| AC-3 | El modelo del código actual reproduce H3 de SE-493 como contraejemplo. Si se elimina del modelo la acción `Respond` perdida, el contraejemplo desaparece (prueba de que la causa es esa y no otra). | calibración |
| AC-4 | Al menos tres escenarios de carrera deliberados se reproducen: (a) revocación entre `Recheck` y `Dispatch`; (b) caída tras `Dispatch` y `Retry` de otro ejecutor; (c) dos ejecutores con el mismo grant de uso único. Cada uno tiene su resultado esperado documentado (violación o no). | positivo |
| AC-5 | Cada contraejemplo genera un test BATS en `tests/formal/` que **falla** contra el código de `origin/main` en la fecha del spike, con `gh` y el reloj simulados. Se demuestra ejecutándolo contra ese commit. | negativo |
| AC-6 | `formal-check.sh` sin herramienta instalada (PATH sin `java`, `tlc` ni `apalache-mc`) sale 4 con `BLOCKED`, nunca 0. | negativo |
| AC-7 | `formal-check.sh` con un límite de tiempo que corta la exploración sale 3 con `UNKNOWN`, nunca 0. | negativo |
| AC-8 | `formal-check.sh` con una salida del checker truncada o sin la línea de fin sale 3. | negativo |
| AC-9 | `formal-check.sh` con un modelo al que se le ha quitado `Recheck` (mutación) sale 1: la violación de I1 se detecta. Si sale 0, el modelo no vale. | mutación |
| AC-10 | En el espacio explorado de los diseños de Fase 2, 0 `Dispatch` no autorizados, o la lista de contraejemplos enviada a las PR de SE-493/496/498. | positivo |
| AC-11 | Ningún documento, commit ni PR de esta spec dice que el software está «probado» o «verificado formalmente» sin la precisión «en el modelo, espacio acotado». Comprobado por grep en el diff. | negativo |
| AC-12 | Ejecutar `formal-check.sh` no realiza ninguna llamada de red ni efecto remoto (stub de `gh` con contador = 0). | negativo |

## Portabilidad

- El modelo es texto TLA+, independiente del frontend y del sistema operativo.
- La herramienta es opcional por instalación: se busca en `PATH` y en una ruta configurable (`SAVIA_FORMAL_TOOLS`). Ninguna ruta personal en el código.
- En CI se puede añadir más tarde como job opcional; si no hay herramienta, el job informa BLOCKED y no bloquea otros jobs, pero **nunca** informa PASS.
- Multioperador: el modelo no tiene identidades; los grants del modelo son abstractos.

## Fuera de alcance

- Corregir los fallos encontrados: cada corrección va a la spec dueña o a una PR propia.
- Modelar SE-149 (ediciones de fichero), la CI o los hooks de PreToolUse.
- Lean u otros asistentes de prueba.
- Probar el software completo o declarar ausencia de bugs.
- Instalar dependencias del sistema.

## Riesgos

- **Modelo infiel**: un modelo que no corresponde al código prueba cosas irrelevantes. Mitigación: calibración con H3 (AC-3), mutación (AC-9) y refinamiento con trazas (Fase 3).
- **Explosión de estados**: mitigación con espacio finito pequeño y `UNKNOWN` honesto si no termina.
- **Mantenimiento**: el modelo deriva si el código cambia. Mitigación: los tests de AC-5 son los que viven en la suite; el modelo se revisa cuando cambie `push-pr.sh`, `operator-grant.sh`, `f5-state.sh` o se implemente SE-493/496/498.
- **Coste**: un spike de 2–3 días de agente; la JVM es el único requisito pesado.

## Plan por slices

1. **S1** — Modelo del código actual, configuración, `formal-check.sh` con los cuatro resultados y sus tests (AC-1, AC-2, AC-6, AC-7, AC-8, AC-9, AC-12).
2. **S2** — Calibración con H3 y los tres escenarios (AC-3, AC-4); tests BATS de contraejemplos (AC-5).
3. **S3** — Modelo de los diseños PROPOSED y comentarios a sus PR (AC-10).
4. **S4** — Comprobador de refinamiento sobre trazas de SE-494 (depende de SE-494).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `formal/authz-effects/*.tla`, `*.cfg` | Ficheros de texto | Los mismos |
| `scripts/formal-check.sh` | Bash desde la sesión | El mismo script |
| `tests/formal/*.bats`, `tests/test-formal-check.bats` | BATS | BATS |

### Verification protocol

- [ ] Funciona en runtime OpenCode: el script no depende del frontend
- [ ] Tests BATS cubren los cuatro resultados de `formal-check.sh`, la mutación y los contraejemplos
- [ ] No añade hooks

### Portability classification

- [x] **PURE_BASH**: bash para el envoltorio; la herramienta externa es opcional y su ausencia da BLOCKED.

## Aprobación

Spec PROPOSED. La aprueba la operadora o la orquestadora con autoridad delegada en su PR. Esta PR solo añade documentación; ningún agente la fusiona sin grant.
