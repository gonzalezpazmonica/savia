---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-02
author: Savia
phase: A
risk: L4
related_specs: [SE-343, SE-433, SE-445, SE-456, SE-488, SE-493]
origin: "Hueco G5 del plan intensivo: las cadenas de evidencia por hash solo se verifican contra sí mismas. Inventario contrastado con main en bbe6ebfdb y con Yema en 93d5e6d."
timeline:
  - from: "2026-11-02"
    learned: "2026-11-02"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-499 — Anclaje externo de cadenas de evidencia

## Problema (verificado en main bbe6ebfdb y en Yema 93d5e6d)

Savia y Yema guardan evidencia en ficheros JSONL encadenados por hash: cada línea lleva el hash de la anterior. Eso detecta que alguien cambie una línea intermedia y deje las demás como estaban. No detecta nada más, porque la cadena solo se compara consigo misma:

1. **Reescritura completa.** Quien puede escribir en el fichero puede regenerarlo entero con la función pública de encadenado y la verificación da «íntegro».
2. **Truncado.** Cualquier prefijo de una cadena válida es una cadena válida. Borrar las últimas líneas no rompe nada.
3. **Borrado.** Un fichero ausente o vacío se verifica como íntegro con cero entradas.

Los tres ataques están al alcance de un agente que trabaja con la cuenta de la persona en la misma máquina, que es justo el actor del que la evidencia debería proteger. Y no son teóricos: en los dos sistemas, **los contadores de presupuesto salen del propio fichero**, así que truncarlo devuelve presupuesto.

### Inventario de cadenas

| Cadena | Dónde vive | Encadenado | Verificación | Qué se pierde al truncar |
|---|---|---|---|---|
| Ledger de merge-sprint (SE-433) | `~/.savia/merge-sprint/ledger.jsonl` (`scripts/merge-sprint.sh:17`, `:22`) | `prev` = sha256 de la línea anterior, `genesis` en la primera (`scripts/merge-sprint.sh:41-49`) | `verify_chain` (`:51-58`); un fichero vacío devuelve 0 (`:53`). Se exige al arrancar `run` (`:567`) y en `verify-ledger` (`:704`) | `merged_count` cuenta los `MERGED` del ledger bajo el grant vigente (`:396-399`): borrar el final permite superar `max_merges` (`:353`). `ledger_merged` (`:390-394`) deja de reconocer un merge ya hecho |
| Registro de revisiones de merge-sprint | `~/.savia/merge-sprint/reviews.jsonl` (`:22`, alta en `:92`) | el mismo `chain_append` | `verify_chain` (`:160`, `:568`) | una revisión `HOLD` borrada del final deja de bloquear (`reviews_ok`, `:97-110`) |
| Registro de veredictos del juez | `~/.savia/merge-sprint/judge.jsonl` (`:22`, alta en `:82`) | el mismo `chain_append` | `verify_chain` (`:569`) | un veredicto se puede quitar sin rastro |
| Recibos del Effect Ledger (SE-493, PROPOSED en la PR #1455) | ledger SQLite por instalación, no implementado | `prev_hash` en cada recibo (spec, Requisito 6) | `verify-receipt` comprueba la cadena y vuelve a observar el remoto (Requisito 6) | la propia SE-493 deja la firma fuera de alcance «junto a los recibos de SE-488» (sección «Fuera de alcance»). Esta spec es ese trabajo |
| Evidencia de Yema por contrato | `<estado>/evidencia/<cid>.jsonl`, con `<estado>` fuera del repo (`nucleo/puerta.py:110-115`, `:865`) | `hash` = sha256(`prev` + cuerpo canónico), génesis `0`×64 (`nucleo/evidencia.py:7-12`, `:22-29`) | `yema evidencia <id>` (`nucleo/yema.py:175-178`); un fichero ausente da «cadena íntegra, 0 recibos» (`nucleo/evidencia.py:15-18`, `:32-41`) | `efectos_usados` cuenta los efectos permitidos del registro (`nucleo/puerta.py:813-815`) y frena el contrato al llegar a `efectos_max` (`:878-881`): truncar devuelve presupuesto de efectos |

Otras cadenas del repo con el mismo patrón y el mismo límite, fuera del alcance de v1: el libro de la relación (`scripts/verify-ledger-chain.sh`, SE-258), el ledger corporativo (`scripts/corporate-ledger-verify.sh`, SE-271) y el ledger de intercambio de federación (`scripts/exchange-ledger.sh:51-57`, SE-263). El registro de ediciones de SE-402 (`scripts/edit-ledger.sh`) no está encadenado.

Hallazgo lateral en Yema: `anotar` (`nucleo/evidencia.py:22-29`) lee el último hash y añade sin cerrojo. Dos escritores concurrentes producen dos líneas con el mismo `prev` y la cadena queda rota de forma legítima. merge-sprint ya lo evita con `flock` (`scripts/merge-sprint.sh:43-44`). Se corrige en S0 de Yema.

### Qué ya está anclado

Las aprobaciones de SE-488 no tienen este problema: su raíz es el commit génesis del repo de aprobaciones fijado en el verificador y la cadena first-parent de `main` (SE-488, R2.1). Su historia la escribe GitHub al fusionar la operadora. Es el modelo que esta spec generaliza.

Los grants de merge de SE-343 tampoco: la firma ed25519 de la operadora se hace con una clave que no está en este equipo y se verifica contra `config/operator-grant-signers` de `origin/main` (`scripts/operator-grant.sh:20-28`, `:75-88`).

### Contexto que limita las opciones

El token de `gh` de esta máquina tiene permiso de administración sobre el repo de Savia (`gh api repos/<repo> --jq .permissions` → `admin: true`, comprobado el 2026-11-02). La protección de `main` (sin force-push, sin borrado, `enforce_admins`) la puede cambiar ese mismo token, y el repo es de usuario, sin registro de auditoría de organización. Ningún anclaje que dependa solo de GitHub y de ese token queda fuera del alcance de un agente que lo use. Sube el coste y la visibilidad del ataque, pero no lo impide.

## Qué decide esta spec

1. Un formato común de **punto de anclaje** para cualquier cadena: qué longitud tenía y cuál era su último hash en un instante.
2. Un verificador común que exige que la cadena **extienda** cada punto de anclaje conocido. Una cadena más corta que un ancla, o con otro hash en esa posición, es `FAIL`, no «íntegra».
3. Tres transportes del punto de anclaje, con coste y garantía distintos, y cuál se usa en cada cadena.
4. El texto que declara el límite en las salidas de verificación **mientras** no haya ancla, para que nadie lea «íntegra» como más de lo que es.

## Alternativas de anclaje

Todas publican el mismo punto de anclaje (Requisito 1). Difieren en quién puede borrarlo o falsificarlo.

### A1 — Comentario en la PR

Tras cada `MERGED`, merge-sprint publica en la PR fusionada un comentario con el punto de anclaje del ledger y del registro de revisiones.

- **Coste:** una llamada a la API por merge (`gh pr comment`), sin preparación ni intervención humana. Cero ficheros nuevos.
- **Garantía:** débil. El comentario lo escribe la misma cuenta que usa el agente, que puede editarlo o borrarlo. GitHub guarda el historial de ediciones de un comentario, pero el borrado no deja rastro visible en un repo de usuario. Detecta una reescritura solo si alguien compara, y deja un registro público con fecha que otra persona puede haber visto o archivado.
- **Exposición:** el repo es público. El punto de anclaje solo contiene longitud y hash; las entradas del ledger son poco entrópicas (número de PR, fecha, tier), así que el hash no oculta mucho, pero tampoco revela nada que la PR no muestre ya. Solo sirve para cadenas cuyo contenido sea ya público, es decir, merge-sprint.
- **Encaje:** solo merge-sprint, porque cada entrada importante tiene su PR. Yema y SE-493 no tienen dónde comentar.

### A2 — Commit en un historial que el agente no reescribe sin dejar rastro

Dos variantes:

- **A2a — Commit en `origin/main` por PR.** Un fichero `anchors/<cadena>.jsonl` en el repo, con una línea por punto de anclaje, que se añade por PR y se fusiona como cualquier otra.
  - **Coste:** una PR y un merge humano por anclaje. Con el flujo de grants por lotes, el ancla llega horas tarde y cada lote añade ruido al historial de `main`. Si se agrupa en la PR de sincronización o en la de cierre del sprint, el coste humano baja a cero adicional, pero la ventana sin ancla es el sprint entero.
  - **Garantía:** media. Reescribir `main` exige cambiar la protección de rama con el token de administración y forzar el push. Eso diverge de todos los clones (otras máquinas, la copia privada sincronizada, CI) y se nota en el siguiente `fetch`. No lo impide el token, lo delata la divergencia.
  - **Exposición:** pública, como A1. No vale para Yema (los identificadores de contrato serían públicos) salvo en un repo privado.
- **A2b — Rama de anclas protegida en un repo privado, con un token sin administración.** Un repo privado de anclas, con un ruleset que prohíbe force-push y borrado en `anchors/*`, creado por la operadora. Los agentes publican con un token *fine-grained* limitado a `contents: write` en ese repo, sin `administration`.
  - **Coste:** preparación única de la operadora (repo, ruleset y token, unos 15 minutos), y después un `git push` de un commit pequeño por anclaje (1–2 s), sin intervención humana. Un token más que custodiar y rotar.
  - **Garantía:** media-alta frente a un agente que solo tenga ese token: puede añadir anclas, pero no reescribir ni borrar las anteriores. **Se pierde si el agente tiene a mano el token con administración** de esta máquina, que hoy existe. Por eso A2b no basta sola mientras ese token siga disponible para los agentes.
  - **Exposición:** privada. Vale para Yema y para SE-493.

### A3 — Firma de la operadora con una clave fuera del equipo (como SE-343)

La operadora firma el punto de anclaje con su clave ed25519, la misma que firma los grants de merge, desde el móvil o desde Savia Space. Namespace propio `savia-evidence-anchor`, distinto de `savia-operator-grant`, para que una firma de ancla no pueda reutilizarse como grant ni al revés. La firma se verifica contra `config/operator-grant-signers` de `origin/main`, con la misma función que `operator-grant.sh`.

- **Coste:** una acción humana por punto de anclaje (abrir la petición en el móvil y firmar, en torno a un minuto). Inviable por merge o por efecto. Viable en hitos: cierre de un merge-sprint, cierre o revocación de un contrato de Yema, resolución manual de un efecto de SE-493.
- **Garantía:** alta. Ningún agente en esta máquina puede fabricar la firma, tenga el token que tenga. Es la única opción cuya garantía no depende de GitHub.
- **Límite:** protege hasta el último punto firmado. Lo escrito después del último hito sigue expuesto a truncado hasta el siguiente.
- **Exposición:** ninguna. La firma se guarda junto a la cadena, fuera del repo.

### Descartadas

- **Sellado de tiempo de terceros (RFC 3161, OpenTimestamps).** Añade una dependencia de red y de un tercero, y prueba el *cuándo*, no el *quién*. No resuelve el truncado mejor que A2b y choca con la soberanía del workspace.
- **Firmar cada entrada con una clave local** (como el HMAC de aprobaciones de Yema, `nucleo/firma.py:10-30`). La clave vive en el mismo equipo que el agente: quien reescribe la cadena también la vuelve a firmar.

### Decisión por cadena

| Cadena | Transporte continuo | Hito firmado (A3) |
|---|---|---|
| merge-sprint (ledger, revisiones, juez) | A1 tras cada `MERGED`, y A2b si está configurada | al terminar `run` (evento `END` o `STOP`) |
| Effect Ledger (SE-493) | A2b | en cada `resolve` manual, que ya exige grant firmado: el punto de anclaje viaja dentro de la misma petición firmada |
| Evidencia de Yema | A2b | al pasar un contrato a un estado terminal o a `suspendido` |

Sin A2b configurada, la cadena queda con A1 (solo merge-sprint) y A3 en hitos, y el verificador lo dice (Requisito 4).

## Requisitos

### R1 — Punto de anclaje

Esquema `savia-anchor/1`, JSON canónico (`sort_keys`, separadores compactos, UTF-8):

- `chain`: identificador opaco de la cadena. Para merge-sprint, `merge-sprint/ledger`, `merge-sprint/reviews` y `merge-sprint/judge`. Para Yema y SE-493, `yema/<h>` y `effects/<h>`, con `<h>` = los 16 primeros hex del sha256 del identificador local, para no publicar identificadores de contrato.
- `install_id`: el de la instalación (el mismo de SE-493), para que dos máquinas no se pisen las anclas.
- `length`: número de entradas.
- `head`: el hash de la última entrada con la regla de esa cadena (sha256 de la línea para merge-sprint, campo `hash` para Yema, `prev_hash` siguiente para SE-493). Cadena vacía: `length: 0`, `head: "genesis"`.
- `ts`: instante UTC.
- `transport`: `pr-comment`, `anchor-branch` o `operator-signed`.

### R2 — Verificador común

`scripts/evidence-anchor.py verify --chain <id> --file <ruta> --anchors <ruta>`, con `python3 -I` y solo stdlib:

1. Verifica el encadenado interno con la regla de la cadena.
2. Para cada punto de anclaje de esa cadena e `install_id`: la cadena tiene al menos `length` entradas y el hash en la posición `length` es `head`. Si no, `FAIL` con el ancla que no se cumple.
3. Salidas: `ANCHORED` (exit 0) si cumple todos los puntos y hay al menos uno; `UNANCHORED` (exit 3) si el encadenado es correcto pero no hay ningún punto; `FAIL` (exit 1) si algo no casa. Un fichero de anclas ilegible, un punto con esquema desconocido o una firma A3 que no verifica dan `FAIL`, nunca `UNANCHORED`: fail-closed.
4. Una cadena ausente o vacía con un punto de anclaje de `length > 0` es `FAIL`. Hoy es «íntegra».

### R3 — Publicación

`scripts/evidence-anchor.py checkpoint --chain <id> --file <ruta> --transport <t>` calcula el punto y lo publica:

- `pr-comment`: necesita `--pr`; publica con `gh pr comment` y guarda el punto también en la copia local de anclas.
- `anchor-branch`: añade la línea a `anchors/<install_id>/<chain>.jsonl` en el clon del repo de anclas y empuja. El remoto y el token salen de la configuración local (`~/.savia/anchors.conf`, fuera del repo). Si el push falla, el punto queda en la copia local marcado `pending` y el siguiente `checkpoint` lo reintenta; `verify` no cuenta un punto `pending` como ancla.
- `operator-signed`: deja la petición canónica sin firmar en `~/.savia/anchors/requests/` y la incorpora con `--signature FICHERO|-`, igual que `operator-grant.sh grant --scope merge`.

La copia local de anclas no es autoridad: `verify` usa la del transporte (comentarios de la PR, rama remota recién traída, firmas válidas). La copia local sirve para trabajar sin red y para detectar que el remoto ha perdido un punto.

### R4 — Texto del límite mientras no haya ancla

Toda salida de verificación de una cadena sin punto de anclaje debe decir lo que no comprueba. Texto exacto, en las salidas de `merge-sprint.sh verify-ledger`, en `yema evidencia <id>` y en `verify-receipt` de SE-493:

> Cadena íntegra respecto de sí misma (N entradas). Sin ancla externa: no detecta que quien escribe en este fichero lo haya reescrito entero, truncado o borrado. Los contadores que salen de él (merges bajo el grant, efectos usados) no están garantizados.

Con anclas, la salida dice además cuál es el último punto, su transporte y cuántas entradas quedan sin anclar después de él:

> Anclada hasta la entrada L (transporte, fecha). Las N−L entradas posteriores solo están protegidas por el encadenado interno.

Una cadena ausente se informa como ausente, no como «íntegra, 0 entradas».

### R5 — Consumo por los contadores

- `merge-sprint.sh run` llama a `verify` en lugar de solo `verify_chain` para las tres cadenas. `FAIL` para con exit 4, como hoy. `UNANCHORED` no para (sería romper todas las instalaciones que no configuren anclas), pero el evento `RUN` registra `anchored=false` y el informe lo muestra.
- Si existe un punto de anclaje para la cadena, `merged_count` no puede devolver menos `MERGED` de los que hay hasta ese punto: lo garantiza R2.2, porque una cadena más corta ya es `FAIL`.
- Yema (PR propia en Yema, S0 y S2): `efectos_usados` verifica la cadena antes de contar. Con `FAIL`, la puerta niega todo efecto material del contrato hasta resolución humana.

## Amenazas y riesgos residuales

- **Token con administración disponible para el agente.** Anula A1 y A2 (puede borrar comentarios, cambiar rulesets y forzar pushes). Solo A3 queda en pie, y solo hasta el último hito. Mitigación fuera de esta spec: que los agentes no usen ese token. La spec lo declara en vez de suponerlo.
- **Ventana entre anclas.** Lo escrito después del último punto se puede truncar. A1 la reduce a cero en merge-sprint (un punto por merge) mientras el comentario siga ahí; A3 la deja en un sprint o un contrato.
- **Borrado de la copia local de anclas.** No basta: `verify` lee el transporte. Con A2b y sin red, `verify` no puede leer el remoto y devuelve `UNANCHORED` con el motivo, no `ANCHORED` con la copia local.
- **Anclas de otra instalación.** Cada punto lleva `install_id` y solo se compara con la cadena de esa instalación. Un agente que cambie el `install_id` local deja la cadena `UNANCHORED`, y eso se ve.
- **Reutilización de firmas.** Namespace propio y petición canónica con `chain`, `install_id`, `length` y `head`: una firma de ancla no vale como grant ni para otra cadena.

## Criterios de aceptación

- **AC-1 — reescritura completa.** Una cadena de merge-sprint regenerada entera con `chain_append` y un contenido distinto, con un ancla previa: `verify` da `FAIL` (exit 1). Sin ancla, `UNANCHORED` (exit 3) y el texto de R4. Negativo: la cadena original con el ancla da `ANCHORED`.
- **AC-2 — truncado.** Quitar la última entrada anclada da `FAIL`. Quitar una entrada posterior al último punto da `ANCHORED` y el texto dice cuántas entradas quedan sin anclar. Caso límite: cadena con exactamente `length` entradas da `ANCHORED`.
- **AC-3 — borrado.** Fichero ausente con un ancla de `length > 0`: `FAIL`. Fichero ausente sin anclas: `UNANCHORED` y «ausente», no «íntegra».
- **AC-4 — contador.** Un `run` de merge-sprint tras truncar los `MERGED` anclados del grant vigente para con exit 4 antes de cualquier merge; con el ledger intacto, continúa. Equivalente en Yema: truncar la evidencia anclada niega el siguiente efecto material.
- **AC-5 — fail-closed.** Fichero de anclas con JSON roto, esquema `savia-anchor/2` o firma A3 inválida (clave ajena, namespace `savia-operator-grant`, contenido alterado en un byte): `FAIL`. `ssh-keygen` ausente con un ancla A3: `FAIL`, no `UNANCHORED`.
- **AC-6 — A3.** Una firma válida de la operadora sobre la petición canónica se acepta solo para su `chain`, `install_id`, `length` y `head`. Una firma de grant de merge sobre los mismos bytes no se acepta (namespace).
- **AC-7 — A2b sin red.** Con el remoto inaccesible, `verify` da `UNANCHORED` con el motivo y nunca `ANCHORED` usando solo la copia local.
- **AC-8 — texto del límite.** Las tres salidas de R4 contienen el texto exacto. Test que falla si se quita una frase.
- **AC-9 — Yema concurrente.** Dos `anotar` concurrentes sobre el mismo registro dejan una cadena íntegra. Hoy el test falla.

Cada AC con test BATS o pytest que falla contra el código actual y pasa después (SE-456).

## Fuera de alcance

- Las cadenas de SE-258, SE-263 y SE-271. Pueden adoptar `evidence-anchor.py` en PRs propias.
- Retirar el token con administración de los agentes, que es lo que daría garantía real a A1 y A2. Es una decisión de la operadora; esta spec solo la deja escrita como condición.
- Crear el repo de anclas, su ruleset y el token *fine-grained*: lo hace la operadora.
- Sellado de tiempo de terceros.
- Cambiar la semántica de SE-488, que ya está anclada por su diseño.

## Plan de implementación

- **S0 — Texto del límite (bajo riesgo).** R4 en `merge-sprint.sh verify-ledger` y en el informe de `run`; en Yema, por PR propia, R4, «ausente» distinto de «íntegra, 0» y cerrojo en `anotar` (AC-3 parcial, AC-8, AC-9). Puede ir antes que el resto.
- **S1 — Formato y verificador.** `scripts/evidence-anchor.py` con R1, R2 y `checkpoint` local; adaptadores de merge-sprint y Yema; AC-1, AC-2, AC-3, AC-5.
- **S2 — Transportes A1 y A2b; consumo en merge-sprint.** R3 y R5. Toca `merge-sprint.sh`, cuyo blob fija el manifiesto (`scripts/merge-sprint.sh:582`): los planes firmados antes quedan inválidos con `anomaly blob_ejecutor`, que es lo correcto, y la PR lo declara. Tier 4, revisión humana explícita. AC-4, AC-7.
- **S3 — A3.** Namespace `savia-evidence-anchor` en `config/operator-grant-signers` y alta en `autonomous-safety-merge-grant-reference.md`; petición y firma; hito al terminar `run`. Toca el sistema de firmas: tier 4. AC-6.
- **S4 — SE-493.** Cuando SE-493 se implemente, su `verify-receipt` usa el verificador y su `resolve` manual incluye el punto de anclaje en la petición firmada.

## Rollback

Revertir S1–S3 devuelve `verify_chain` y la salida actual. Los ficheros de anclas quedan inertes. S0 no tiene nada que revertir salvo el texto.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Verificador y publicación | `scripts/evidence-anchor.py` | el mismo script |
| merge-sprint | `scripts/merge-sprint.sh` | el mismo script; no depende del frontend |
| Yema | `nucleo/evidencia.py`, `nucleo/puerta.py` (repo de Yema) | los mismos; la puerta de Yema ya se invoca igual desde ambos |

### Verification protocol

- [ ] Los tests ejecutan `evidence-anchor.py` con `python3 -I`, sin pasar por ningún hook de frontend.
- [ ] Ningún plugin TS reimplementa la verificación.

### Portability classification

- [x] **PURE_BASH**: bash más Python stdlib (`hashlib`, `json`, `subprocess` para `ssh-keygen` y `git`), sin bindings de frontend.
