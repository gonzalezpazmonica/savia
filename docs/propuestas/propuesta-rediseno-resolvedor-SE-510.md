# SE-510 F3 — Rediseño: comprobar el resumen de PR al ejecutar `gh`, no adivinarlo del texto

> Propuesta de gobernanza. **No implementada.** Decide la operadora.
> Spec: `docs/specs/SE-510-guardas-sin-bloqueos-falsos-despachador.spec.md` (F3, AC-2, AC-10).

## Qué problema queda

`pr-summary-gate.sh` lee `.pr-summary.md` de `$CLAUDE_PROJECT_DIR`, no del árbol donde se
ejecuta `gh pr create`. Desde un worktree, el gate mira el resumen de otra carpeta: bloquea un
resumen bueno (F3, bloqueo falso) o deja pasar uno que no existe (falso permiso).

La primera solución (rama de la PR #1596, `scripts/lib/pr_summary_root.py`) deduce ese
directorio **leyendo el texto de la orden bash** antes de que corra: sigue un `cd` literal al
principio y bloquea todo lo que no entiende. Cuatro rondas de revisión independiente han
encontrado, cada vez, construcciones nuevas de la misma clase que cambian el directorio sin que
el lector lo vea:

| Ronda | Construcción que el lector no entendía |
|---|---|
| 1 | varios `cd`, `cd` en subshell cerrado, `pushd`/`popd`, `env -C` |
| 2 | `c\d`, `c''d`, `cd` en segundo plano con `&`, continuaciones `\`+salto |
| 3 | `env -C<ruta>`, `env -iC`, `builtin pushd`, `\gh`, `"gh"`, `c$'d'`, `${x}d`, `source` |
| 4 | `command .`, `builtin .`, `.` tras `then`/`do`, `CDPATH` heredado |

La causa no es una construcción concreta: **el texto de una orden bash no determina el
directorio en que se ejecutará** sin ejecutar bash (alias, funciones, `CDPATH`, ficheros
sourced, variables, `eval`). Cada parche cierra un caso y deja la clase abierta. Seguir por
ahí es pagar una ronda de revisión por cada construcción que alguien recuerde.

## La alternativa: un envoltorio que pregunta al sistema dónde está

En lugar de adivinar, se comprueba **en el momento de ejecutar `gh`**, desde el propio proceso:

1. Un ejecutable `gh` de Savia (por ejemplo `scripts/bin/gh`) va primero en el `PATH` de las
   sesiones de agente.
2. Cuando lo invocan con `pr create`, lee su directorio real (`os.getcwd()`) y la raíz del
   árbol (`git rev-parse --show-toplevel`, que también resuelve worktrees).
3. Comprueba el `.pr-summary.md` de **esa** raíz con la misma lógica que hoy el gate
   (encabezado, longitud, antigüedad, revisión con modelo).
4. Si pasa, ejecuta el `gh` real (buscado en el `PATH` saltándose a sí mismo) con los mismos
   argumentos. Si no pasa, sale con código distinto de 0 y el mismo mensaje que hoy.
5. Cualquier otra orden de `gh` (`pr view`, `api`, …) pasa directa, sin coste.

`cd`, `pushd`, `CDPATH`, `source`, `command .`, alias, funciones o `eval` dejan de importar:
cuando el proceso `gh` arranca, el sistema ya ha resuelto el directorio.

### Ventajas

- **Cierra la clase, no casos.** No hay lector de bash que mantener; desaparece
  `pr_summary_root.py` (222 líneas) y sus ~40 tests de construcciones.
- **Sirve igual para Claude Code, OpenCode y la terminal** si el `PATH` lo incluye: la paridad
  bash/TS del gate sale gratis (hoy está marcado `not_exposed`).
- **Sin bloqueos falsos por forma.** `cd "$WT" && gh pr create` funciona como espera la persona.
- **Coste cero en el camino que no es `gh pr create`.**

### Límites: qué lo esquiva

El envoltorio solo ve lo que pasa por él. No lo ven:

| Ruta | Ejemplo | Se puede cerrar con |
|---|---|---|
| `gh` por ruta absoluta | `/usr/bin/gh pr create` | regla simple en el hook: bloquear `pr create` invocado por ruta que no sea el envoltorio (texto, pero un caso acotado y estable) |
| `PATH` reescrito | `env -i …`, `PATH=/usr/bin gh …`, `command -p gh` | la misma regla, o aceptarlo como hueco conocido |
| Otros clientes | `gh api` con `createPullRequest`, `curl` a la API, herramientas MCP de GitHub, la web o la app | solo una comprobación del lado del servidor (siguiente punto) |
| Sesiones sin el `PATH` de Savia | una terminal fuera de la sesión de agente | es lo deseado: el gate es para agentes |

**Una comprobación en CI del cuerpo de la PR** (una Action que falle si el body no tiene el
encabezado y el mínimo de texto) cubre todos los clientes, porque mira el resultado y no cómo se
creó. No sustituye al envoltorio (llega después de abrir la PR, no antes), pero es la red que
hace que esquivarlo no sirva de nada.

### Qué no resuelve

- Que el resumen sea bueno: eso sigue siendo la revisión con modelo y la revisión humana.
- La latencia de la revisión con modelo: se mueve del hook al envoltorio, no desaparece.

## Decisiones para la operadora

Listas para pregunta interactiva; la opción marcada es la recomendada.

1. **Qué hacer con el lector de texto de #1596.**
   - (a) **Retirarlo y pasar al envoltorio** — *recomendada*: cierra la clase de fallo.
   - (b) Mantenerlo y seguir parcheando: cada ronda de revisión encontrará otra construcción.
   - (c) Mantenerlo como primera barrera además del envoltorio: duplica superficie sin cerrar nada que el envoltorio no cierre.
2. **Dónde se pone el envoltorio en el `PATH`.**
   - (a) **Un hook de inicio de sesión que lo antepone** (vía el fichero de entorno de la sesión) — *recomendada*: no toca `settings.json`.
   - (b) La sección `env` de `settings.json`: más directa, pero es tier 4.
   - (c) Que cada persona lo añada a su shell: frágil y depende de cada instalación.
3. **Qué hacer con `gh` por ruta absoluta o con `PATH` reescrito.**
   - (a) **Regla acotada en el hook** que bloquea `pr create` fuera del envoltorio — *recomendada*: es un patrón corto y estable, no un intérprete de bash.
   - (b) Aceptarlo como hueco conocido y documentado.
4. **Comprobación del lado del servidor.**
   - (a) **Añadir una Action que valide el cuerpo de la PR** — *recomendada*: cubre todos los clientes.
   - (b) No añadirla: el envoltorio queda como única barrera.
5. **Qué pasa con la PR #1596.**
   - (a) **Cerrarla tras fusionar la parte independiente**, dejándola enlazada como antecedente — *recomendada*.
   - (b) Dejarla abierta en borrador hasta tener el envoltorio.

## Qué haría falta después (si se aprueba)

Enmienda de SE-510 (F3 y AC-10: «el gate lee el resumen del árbol donde se ejecuta `gh`» pasa a
cumplirse en ejecución), slice nueva con sus tests (cada vía de la tabla de límites como caso
negativo) y retirada del caso `not_exposed` de `pr-summary-gate` en `config/guard-ts-parity.json`.
