---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-30
author: Savia
phase: D
risk: L4
related_specs: [SE-343, SE-433, SE-362, SPEC-186]
origin: decisión de la operadora 2026-10-30 (AskUserQuestion, «Solo GitHub») — opera la metaorquestación solo desde el móvil (chat y app de GitHub), sin terminal ni edición de ficheros; diseño previo en el vault privado de investigación
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-488 — Aprobaciones por fusión de PR (operación solo móvil)

## Problema (verificado en origin/main 3e24baa8f)

La operadora gobierna desde el móvil: el chat del asistente y la app de GitHub.
No tiene terminal ni edita ficheros. Varias aprobaciones que **amplían** la
autoridad de un agente exigen hoy una terminal o una firma local:

1. **Contratos de Yema.** `yema aprobar`, `activar` y `transicion → aprobado|activo`
   exigen una TTY o un ticket de 5 minutos. Ese ticket lo deja la puerta tras el
   diálogo de permisos de una sesión **local** (`nucleo/yema.py::_persona_presente`).
   Una enmienda es otra huella y se reaprueba igual.
2. **Grants de merge (SE-343, SE-433 D7).** `scripts/operator-grant.sh` exige una
   firma ed25519 de la operadora (`ssh-keygen -Y sign`): en el móvil hace falta un
   emulador de terminal y pegar ficheros.
3. **Settings locales no versionados.** Solo se cambian editando en el equipo.

El push forzado **no** necesita esta vía. `.claude/hooks/block-force-push.sh`
ya permite `--force-with-lease` en ramas que no son `main` (lo exige el rebase de
PRs en cola, SPEC-105). Hacia `main`, y con `--force`, `+refspec` o `--mirror`,
lo prohíbe por diseño: es una prohibición, no algo que se apruebe. Esta spec no
lo cambia.

Ya son móviles: el merge de PRs (botón de la app), la aprobación de specs
(pregunta en el chat) y suspender o revocar (reducen autoridad, sin aprobación).

El clasificador del arnés impide, con razón, que un agente se construya su propia
vía de aprobación: tickets, scripts o reglas de permiso. Hace falta una vía que
la operadora pueda usar desde el móvil y que ningún agente pueda imitar.

## Decisión

Toda aprobación que amplíe la autoridad de un agente es **una PR en un repo
privado de aprobaciones**. La operadora la **fusiona** en la app de GitHub: ese
merge es el acto humano. Yema y Savia verifican el **commit de merge**, sin red,
contra un espejo local. Lo que reduce autoridad no cambia.

## Requisitos

### R1 — Artefacto de aprobación
- La PR añade **exactamente un fichero**: `aprobaciones/<tipo>/<fecha>-<id>-<nonce8>.json`.
  Tiene una lista blanca: `<tipo>` pertenece a un enum cerrado, `<id>` casa con
  `^[a-z0-9-]{1,64}$`, `<fecha>` es `AAAAMMDD` y `<nonce8>` son 8 hex. No se
  admiten `/`, `..` ni caracteres fuera de ASCII.
- Esquema `aprobacion/1`: `tipo`, `nonce` (16 hex aleatorios), `emitida`,
  `caduca` (≤ 24 h), `objeto` y `resumen` en lenguaje llano.
- Objetos por tipo:
  - `yema-contrato`: `{id, huella}`, con la huella sha256 **completa**;
  - `savia-merge`: `{repo, prs: [{numero, head_sha}]}`, que admite lotes;
  - `savia-settings`: `{fichero, sha256_antes, sha256_despues, diff}`. El `diff`
    es legible y el verificador comprueba que lleva de `sha256_antes` a
    `sha256_despues`.
- El `resumen` se genera de forma determinista a partir del `objeto`. El
  verificador lo **regenera y rechaza** el fichero si no coincide byte a byte. El
  cuerpo de la PR muestra el `objeto` literal. La herramienta que abre la PR la
  ejecuta un agente, así que el cuerpo no es una defensa. Lo que se aprueba es el
  `objeto` que la operadora ve en el fichero, el único que la PR cambia.

### R2 — Recibo de merge verificable sin red
Un recibo vale solo si se cumplen todas estas condiciones, comprobadas sobre el
espejo local del repo de aprobaciones:
1. `M` está en la cadena first-parent de `main` del espejo, y esa cadena llega
   al **commit génesis del repo de aprobaciones, fijado en el verificador**.
   Cada commit de la cadena, salvo el génesis, cumple R2.2–R2.5. Así, un merge
   firmado de otro repo (p. ej. una PR de `savia` que añadiera un fichero
   `aprobaciones/…`) no se puede trasplantar: su primer padre no desciende del
   génesis por una cadena de aprobaciones. El espejo solo avanza por
   **fast-forward**: si `main` se reescribe, no hay aprobación hasta que la
   operadora lo revise.
2. `M` tiene dos padres. El repo solo permite *merge commits*.
3. `git verify-commit M` es válido con la **clave pública de web-flow de GitHub
   fijada en el repo verificador**, no con el llavero del usuario.
4. El autor de `M` es la identidad configurada de la operadora.
5. `git diff --name-status M^1 M` tiene **una sola entrada**, de tipo `A`
   (alta): sin modificaciones, borrados, renombrados ni cambios de modo. Su ruta
   casa con `aprobaciones/<tipo>/<fecha>-<id>-<nonce8>.json`, donde `<tipo>`,
   `<id>` y `<nonce8>` coinciden con los campos del fichero.
6. El fichero cumple el esquema `aprobacion/1`: `nonce` de 16 hex y
   `caduca − emitida ≤ 24 h`. Su `objeto` casa con el esperado, con la huella
   idéntica. El verificador impone los límites aunque el fichero diga otra cosa:
   una ventana de un año no vale.
7. `ahora < caduca`, y la fecha de commit de `M` está en `[emitida, caduca]`.
   `ahora` es el reloj local, y el verificador no tiene una fuente de tiempo de
   confianza sin red. Por eso se fija un **suelo monótono**: `ahora` debe ser
   igual o posterior a la marca más reciente que el verificador ya ha visto.
   Esa marca es la mayor entre:
   - la fecha firmada de la punta de `main` del espejo;
   - la fecha de cada `M` verificado;
   - el último `ahora` aceptado, que se guarda en el libro de consumidos.

   Si `ahora` es anterior a ese suelo, no hay aprobación. Con red, además, la
   fecha del servidor (`Date` de la respuesta de GitHub) sustituye a `ahora`.
   **Riesgo residual declarado:** un agente que controle el reloj del proceso
   (p. ej. `faketime`) y que además impida sincronizar el espejo puede usar
   tarde un recibo **aún no consumido**. Solo sirve para lo exactamente
   aprobado y una sola vez, porque el libro de consumidos lo sigue limitando. La
   caducidad acota la vigencia nominal, no la efectiva frente a ese adversario.
8. El libro de consumidos local registra cada uso por `(nonce, unidad)`. La
   unidad es el contrato, la PR del lote o el fichero de settings. Una unidad ya
   anotada no vale. Orden fail-closed: bajo un cerrojo exclusivo (`flock`) se
   comprueba, **se anota como consumido y después se ejecuta la acción**. Si la
   acción falla, el recibo queda gastado y hace falta otro. Nunca queda una
   acción hecha con el recibo aún reutilizable. Dos usos concurrentes no pasan
   los dos. En un lote `savia-merge`, cada PR se consume por separado y las
   demás siguen vigentes. Borrar el libro reinicia los consumos **y** baja el
   suelo de R2.7 hasta la fecha de la punta del espejo: los dos efectos figuran en
   la tabla de amenazas.
9. El tipo está **habilitado por separado** en la política del consumidor. No hay
   un interruptor global: un tipo no habilitado no se acepta.

Cualquier fallo, herramienta ausente (`git`, `gpg`), clave no fijada o espejo sin
sincronizar da **no aprobado**: fail-closed. `merged_by` de la API se guarda como
evidencia cuando hay red, pero no decide.

### R3 — Separación de identidades (mitigación recomendada)
GitHub no distingue un merge de la app de uno por API si ambos usan credenciales
de la misma cuenta. En plan gratuito, además, un repo privado no admite rulesets
ni protección de rama (verificado: la API responde 403). Por eso:
- los agentes abren las PRs con una **GitHub App propia**, instalada **solo** en el
  repo de aprobaciones, con `contents:write` y `pull_requests:write` y sin
  `administration`. Si la App fusiona, el merge sale con autor bot y R2.4 lo
  rechaza;
- el token personal de la máquina **excluye** el repo de aprobaciones: el
  verificador de instalación exige 404;
- el espejo se sincroniza con una **deploy key de solo lectura**;
- defensa en profundidad: un guard bloquea `gh pr merge`, `gh api …/merge` y
  `…/reviews` contra el repo de aprobaciones;
- un ruleset (1 aprobación, sin bypass) es una mejora opcional si hay plan de
  pago. La verificación de R2 no depende de él.

Alternativas descartadas:
- **PAT sin permiso de merge.** Para abrir la PR hay que empujar una rama, y eso
  exige `contents:write`, que en fine-grained ya permite fusionar.
- **Solo ruleset.** Es de pago en un repo privado, y no impide que un token de
  la misma cuenta apruebe y fusione.
- **Solo guard.** Ve texto: es defensa en profundidad, no frontera.

### R4 — Consumidores
- **Savia:**
  - `operator-grant.sh check --scope merge` acepta un recibo `savia-merge` como
    alternativa a la firma ed25519. Se mantienen el `head_sha` exacto,
    `--match-head-commit`, el uso único y el máximo de 24 h;
  - `block-force-push.sh` **no cambia** (ver «Problema»);
  - en la vía de `operator-grant.sh`, el recibo se consume (`consume`) **antes**
    de `gh pr merge`, bajo el mismo cerrojo que la comprobación (R2.8). Si el
    merge falla, el recibo queda gastado;
  - una herramienta aplica un cambio de settings locales solo si el sha256 previo
    y el resultante casan con un recibo `savia-settings`.
- **Yema:** ver R5.

### R5 — Cambios en Yema (los implementa una PR propia en Yema tras aprobar esta spec)
- `_persona_presente(raiz, cid, h8, tty)` acepta un tercer camino, además de la
  TTY y el ticket: un **recibo de merge** (R2) de tipo `yema-contrato` para `cid`
  cuya huella completa empiece por `h8` y coincida con `contrato.huella(c)`. El
  recibo **no se borra**: se anota en `aprobaciones/consumidos.jsonl` con la
  unidad `cid@huella`, bajo cerrojo y **antes** de la transición (R2.8). Si la
  transición falla, hace falta otro recibo.
- `activar` y `transicion` a un estado de `HUMANAS` aceptan el mismo recibo.
- La evidencia anota `via: "github:<sha12>"`.
- `gobierno/politica.json` incorpora `aprobacion_github`: ruta del espejo, autor
  esperado, ruta de la clave web-flow fijada, commit génesis del repo de
  aprobaciones, caducidad máxima y tipos habilitados (solo `yema-contrato`). Sin
  esa sección, el camino está apagado.
- Órdenes nuevas:
  - `yema solicitar <id>`: crea el artefacto y abre la PR con la App; sin App,
    imprime el artefacto;
  - `yema sincronizar`: `git fetch` del espejo.
- Sin red, la verificación lee el espejo y la clave fijada. Sin sincronizar, no
  hay aprobación.

### R6 — Flujo móvil
Una aprobación cuesta **3 toques** desde la notificación: abrir la PR, «Merge
pull request» y «Confirmar». Con un ruleset de aprobación serían 6. Las cifras
son estimadas y se miden en el piloto (AC-8).

## Amenazas

| Amenaza | Defensa |
|---|---|
| PR fabricada y fusionada por un agente | R3: sin credencial de la operadora para ese repo. Un merge de la App falla en R2.4; un commit local o reescrito falla en R2.3 |
| PR engañosa (el cuerpo no coincide con el fichero) | El cuerpo lo escribe el lado de los agentes, así que no es una defensa. El verificador regenera el `resumen` desde el `objeto` y rechaza si difiere (R1); el cuerpo muestra el `objeto` literal; R2.5 exige un solo fichero, que es lo que la operadora ve |
| Trasplante de un merge legítimo de otro repo (p. ej. una PR de `savia` con un fichero `aprobaciones/…`), empujado por la App al `main` del repo de aprobaciones | R2.1: la cadena first-parent debe llegar al génesis fijado y estar hecha toda de merges aprobados; el espejo solo avanza por fast-forward |
| La App reescribe `main` del repo de aprobaciones (no hay ruleset en plan gratuito) | Fast-forward obligatorio en el espejo (R2.1): una reescritura deja sin aprobación, fail-closed |
| Reutilización | Libro de consumidos por `(nonce, unidad)` bajo cerrojo; el objeto ata id y huella (o PR y `head_sha`); caducidad |
| Ventana de vigencia inflada por el agente que redacta el fichero | R2.6 impone `caduca − emitida ≤ 24 h` sea cual sea el contenido |
| Reloj local atrasado o manipulado | Suelo monótono y fecha del servidor cuando hay red (R2.7). Riesgo residual declarado: con el reloj controlado y sin sincronizar, un recibo no consumido se puede usar tarde, una vez y solo para lo aprobado |
| Borrado del libro de consumidos | Reinicia los consumos y baja el suelo de R2.7 hasta la fecha de la punta del espejo. Solo permite repetir lo idéntico dentro de la vigencia (el mismo límite que `merge.spent`) |
| `<id>` o `<tipo>` con `/`, `..` o caracteres confundibles | Lista blanca de R1, comprobada en R2.5 |
| Contrato cambiado tras aprobar | La huella sha256 del contenido material no casa (R2.6) |
| Caducidad | `caduca` ≤ 24 h y la fecha firmada de `M` dentro de la ventana |
| Rotación de la clave de web-flow | Se actualiza por PR fusionada por la operadora; mientras tanto, fail-closed |
| Otra credencial de la operadora en la máquina | Auditoría en el verificador de instalación (AC-6). Es un requisito, no algo que garantice el código |

**Supuesto por verificar (AC-7):** un commit creado por API por la App, con el
autor puesto a mano con la identidad de la operadora, **no** lleva firma de
web-flow. Si fallara, R2 debe exigir además `merged_by` con red, y el diseño
vuelve a revisión.

## Criterios de aceptación

- **AC-1:** el verificador de recibos acepta un merge commit firmado por
  web-flow, con autor de la operadora y un solo fichero válido (fixture con una
  clave de prueba en lugar de web-flow). Rechaza cada caso por separado (un test
  por condición de R2):
  - sin firma;
  - firma de otra clave;
  - autor bot;
  - un solo padre;
  - más de dos padres (octopus);
  - dos ficheros;
  - `M` fuera de la cadena first-parent de `main`;
  - un merge válido trasplantado de otro repo (su cadena no llega al génesis);
  - un commit intermedio de la cadena que no es un merge aprobado;
  - un espejo cuyo `main` se reescribió (no fast-forward);
  - un `<id>` con `/`, `..` o caracteres fuera de ASCII, o un `<tipo>` fuera del enum;
  - un `resumen` que no coincide con el regenerado;
  - un tipo no habilitado en la política;
  - `savia-settings` con un `diff` que no lleva de `sha256_antes` a `sha256_despues`;
  - una entrada `M` (modifica un fichero existente) en vez de `A`;
  - un borrado, un renombrado o un cambio de modo;
  - `ahora` anterior al suelo monótono;
  - una ruta que no casa con el tipo, el id o el nonce;
  - esquema o nonce inválidos;
  - `caduca − emitida` > 24 h;
  - huella distinta;
  - caducado;
  - fecha de `M` fuera de la ventana;
  - ya consumido.
- **AC-1b:** en un lote `savia-merge` de dos PRs, consumir la primera no
  invalida la segunda, y reusar la primera falla. Dos procesos concurrentes
  sobre la misma unidad: pasa uno y solo uno (test con dos procesos). Si la
  acción falla después de consumir, el recibo no vuelve a valer (test).
- **AC-2:** si falta `gpg` o la clave fijada, o el espejo no tiene la rama, el
  resultado es **no aprobado** (test).
- **AC-3:** `operator-grant.sh check --scope merge` con recibos. Hoy el python
  de `check` solo sale con 0 o 1, y el 2 se reserva a errores de entorno. El
  código 2 para recibos es **nuevo**. Cada condición da un código y solo uno:
  - 0: recibo `savia-merge` válido para `pr:<n>` con su `head_sha`;
  - 1 (no vigente): recibo bien formado y anclado, pero la cabeza difiere, está
    caducado (R2.7), consumido (R2.8) o por debajo del suelo;
  - 2 (inválido): falla cualquier condición estructural (R2.1–R2.6 o R2.9) o el
    recibo es de otro repo;
  - 3: no hay ni grant ni recibo.

  Se prueba con bats, un caso por código.
- **AC-4:** no regresión: `block-force-push.sh` no se modifica y sus tests
  actuales siguen en verde, incluido `--force-with-lease` a ramas que no son
  `main`, que exige SPEC-105.
- **AC-5:** en Yema, `yema aprobar` sin TTY ni ticket pasa con un recibo válido y
  falla con uno consumido o con otra huella (pytest, en la PR de Yema).
- **AC-6:** el verificador de instalación falla si el token de la máquina ve el
  repo de aprobaciones, o si la App tiene `administration`.
- **AC-7:** prueba real con la App: un intento de crear por API un commit con el
  autor de la operadora falla R2.3 o R2.4. El resultado se documenta.
  **Puerta:** pasar a APPROVED exige que el resultado de AC-7 esté documentado
  y sea favorable. Si no lo es, la spec vuelve a PROPOSED con R2 rediseñado.
- **AC-8:** piloto en el móvil: se registran los toques reales de cada tipo de
  aprobación.
- **AC-9:** guard, `validate-ci-local.sh --quick` y SAM FRESH en verde.

## Rollback

- Las vías actuales (TTY, ticket, firma ed25519) **se mantienen**. El recibo es
  un camino adicional que se apaga quitando `aprobacion_github` de la política de
  Yema y la configuración equivalente de Savia.
- Quitar la App y la deploy key invalida la emisión de nuevos recibos. Los ya
  consumidos quedan en la evidencia.

## Fuera de alcance

- Implementar Yema en esta spec (R5 va en una PR de Yema tras aprobarla).
- Crear el repo, la App o la deploy key: eso lo hace la operadora en su cuenta.
- Cambiar la aprobación de specs (ya es móvil) o la protección de `main` de Savia.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Verificador de recibos | `scripts/approval-receipt.py` (CLI, sin dependencias del frontend) | mismo script |
| Grant de merge | `scripts/operator-grant.sh` | mismo script |
| Guard del repo de aprobaciones | hook PreToolUse sobre `gh` | plugin savia-gates |

### Verification protocol

- [ ] El verificador es un CLI puro: mismo veredicto desde ambos frontends.
- [ ] Los hooks reciben el evento por stdin en ambos bindings.

### Portability classification

- [x] **DUAL_BINDING**
