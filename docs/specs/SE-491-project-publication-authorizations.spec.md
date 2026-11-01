---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-01
author: Savia
phase: A
risk: L4
related_specs: [SE-343, SE-425, SE-445, SE-456, SE-488]
origin: "Hallazgo de la PR #1444 (2026-10-31): el fichero de autorizaciones de publicación está versionado y cualquier agente puede escribirlo. La operadora aprobó redactar la spec el 2026-11-01."
timeline:
  - from: "2026-11-01"
    learned: "2026-11-01"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-491 — Autorizaciones de publicación de proyectos que un agente no puede fabricar

## Problema (verificado en origin/main 6be70ecb2)

Un proyecto dentro de `projects/` es privado salvo que `.gitignore` tenga una línea `!projects/<nombre>/`. Esa línea lo publica en un repo público. La regla dice que solo la operadora decide publicar, con el gesto `bash scripts/protect-project-privacy.sh --authorize <nombre>`, que pide escribir «SÍ PÚBLICO».

Hoy ese gesto no protege nada:

1. **La autorización es un fichero de texto versionado.** `--authorize` añade el nombre a `.claude/.project-authorizations`, que está en el repo. Cualquier agente puede escribir una línea en él con `Edit`, `Write`, `echo >>` o `sed`, y ningún guard lo impide. El efecto es el mismo que el gesto humano.
2. **El «SÍ PÚBLICO» no prueba que haya una persona.** Un agente puede responder a la pregunta enviando el texto por una tubería (`printf 'SÍ PÚBLICO\n' | bash scripts/protect-project-privacy.sh --authorize x`). `read` no exige un terminal.
3. **Los consumidores no se ponen de acuerdo:**
   - `scripts/protect-project-privacy.sh --hook` (pre-commit) consulta el fichero solo para las líneas nuevas de `.gitignore`. La verificación 2, la de ficheros en `projects/`, mira la whitelist de la copia de trabajo, que un agente también puede editar.
   - `.claude/hooks/block-gitignored-references.sh` compara las referencias `projects/<x>/` con la whitelist del `.gitignore` de la copia de trabajo y nunca mira las autorizaciones. Bloquea el caso autorizado (el incidente del 2026-10-31). Una línea añadida con `sed` le basta para dejar pasar cualquier referencia.
   - `block-gitignored-references.ts` (OpenCode) no tiene la regla de proyectos en main. La PR #1444, aún abierta, la añade y lee el mismo fichero editable.
   - `.claude/hooks/block-project-whitelist.sh` bloquea toda línea `!projects/` nueva en `.gitignore`, también la autorizada. Su mensaje pide ejecutar `--authorize`, pero no lo consulta. En OpenCode no existe: no hay port TS y el plugin no ejecuta ese hook bash.
4. **Las escrituras por Bash no pasan por los guards de Edit/Write.** `sed -i`, `>>` o `tee` sobre `.gitignore` solo se detectan al hacer commit, y el hook de commit es local y se puede desactivar.
5. **El fichero actual mezcla cosas.** Tiene 6 líneas:
   - `proyecto-alpha`, `proyecto-beta`, `sala-reservas` y `savia-mobile-android` están autorizados y en la whitelist;
   - `claude-code-templates` está autorizado pero no está en la whitelist;
   - `savia-vaults/package-lock.json` es un fichero suelto que el parser trata como si fuera un proyecto.

   En la whitelist hay además cuatro proyectos sin autorización registrada: `savia-monitor`, `savia-web`, `savia-vaults` y `savia-sonora`.

La causa de fondo es que el estado de la copia de trabajo cuenta como autoridad. Todo lo que un agente puede escribir en la copia de trabajo, el fichero de autorizaciones o el `.gitignore`, acaba concediendo permisos.

## Qué decide esta spec

Se separan dos preguntas que hoy se mezclan:

- **¿Qué ya es público?** Lo que dice la whitelist del `.gitignore` **de `origin/main`**, que solo cambia con una PR fusionada por una persona. La whitelist de la copia de trabajo no concede nada a ningún guard.
- **¿Quién puede publicar algo nuevo?** Solo una **autorización firmada** por una clave de operador registrada, que un agente no puede producir. La firma reutiliza el mecanismo de los grants de merge (SE-343): `ssh-keygen -Y` con ed25519 contra `config/operator-grant-signers` de `origin/main`, pero con un namespace propio.

Así, escribir en la copia de trabajo deja de servir para autorizarse. Además, la autorización firmada se puede versionar en el repo público sin riesgo, porque copiarla no sirve para otro proyecto ni para otro repo, y nadie puede fabricarla.

## Alternativas

Se compararon cuatro. Las cuatro tienen argumentos a favor; la tabla los pone en paralelo.

| | A. Firma versionada en el repo | B. Firma en el estado privado | C. HMAC con clave local | D. Solo la fusión de la PR |
|---|---|---|---|---|
| Dónde vive | `config/project-authorizations/<nombre>.json` + `.sig` | `~/.savia/project-authorizations/` | `~/.savia/` con un secreto en el mismo equipo | En ningún sitio: la autorización es la PR fusionada que añade la línea |
| ¿Un agente con el mismo usuario puede fabricarla? | No: le falta la clave privada, que está en el móvil | No, por la misma razón | **Sí**: lee el secreto igual que la operadora | No, si la PR exige revisión humana |
| ¿La CI puede verificarla? | Sí: está en el árbol de la PR | No: la CI no ve `~/.savia` | No | Sí: la CI ve el diff |
| Instalación nueva o segundo equipo | Llega con el clon | Se pierde: hay que volver a firmar en cada equipo | Se pierde | Funciona sin estado local |
| Operadora solo desde el móvil | Firma en el móvil; el agente incorpora la firma | Igual | Necesita un terminal | Fusiona desde la app de GitHub |
| ¿Deja guiar al agente antes de la fusión? | Sí: con la firma, el agente puede editar `.gitignore` | Sí, en ese equipo | Sí, pero no es una frontera | No: hasta la fusión, ningún guard local sabe que está autorizado, así que el agente no puede preparar la PR |
| Qué hace público | El nombre del proyecto en cuanto se firma (se iba a publicar) | Nada | Nada | El nombre, en la PR |
| Dependencias | Clave registrada en el fichero de firmantes | Igual | Ninguna | GitHub y la regla de revisión |
| Revocación | PR que borra el fichero y añade el nonce a `REVOKED` | Borrar el fichero local, aunque una copia guardada lo revive | Rotar el secreto | PR que quita la línea |

**C se descarta.** Un HMAC con el secreto en el mismo equipo y el mismo usuario no separa a la operadora del agente. Solo frena errores accidentales, y para eso ya está el bloqueo actual.

**D es la más simple y no necesita clave**, pero no resuelve el caso que originó la PR #1444. El agente tiene que poder escribir la línea y referirse al proyecto **antes** de la fusión, y con D ningún guard local puede distinguir el caso autorizado del no autorizado. Por eso se mantiene como **suelo**: en una instalación sin clave registrada, publicar sigue siendo posible, pero solo con una edición humana y una PR de tier 4.

**Entre A y B se elige A.** B esconde el nombre hasta la publicación y no deja nada en el repo. A cambio, la CI no puede comprobarla y obliga a firmar de nuevo en cada equipo y en cada instalación nueva, lo que choca con el requisito de funcionar para cualquier operador. El nombre que A hace público es el de un proyecto que se va a publicar justo después, y la operadora puede negarse a firmar sin que quede nada escrito, porque la petición vive en `~/.savia`.

**Recomendación: A como mecanismo y D como suelo para instalaciones sin clave.**

## Requisitos

### R1 — Petición y firma

- `protect-project-privacy.sh --authorize <nombre>` ya no escribe ninguna autorización. Hace esto:
  1. Valida el nombre: `^[a-z0-9][a-z0-9_-]{0,63}$`, sin `/` ni `..`.
  2. Escribe la petición canónica en `~/.savia/project-authorizations/<nombre>.request`, **fuera del repo**:
     - `schema`: `project-authorization/1`;
     - `project`;
     - `repo`: el remoto `origin` normalizado a `host/propietario/repo`;
     - `grantor`: la identidad del firmante;
     - `issued`, en formato ISO;
     - `nonce`: 16 caracteres hexadecimales aleatorios;
     - `declaracion`: el texto fijo de la lista actual (sin datos de clientes, sin información confidencial, sin NDA y con permiso para publicarlo).
  3. Muestra en lenguaje llano qué se va a publicar y la orden de firma: `ssh-keygen -Y sign -f <clave> -n savia-project-publish <petición>`.
  4. Sale con 4, como `operator-grant.sh grant`.
- `--authorize <nombre> --signature <fichero|->` verifica la firma (R2). Si es válida, escribe en el repo `config/project-authorizations/<nombre>.json`, con los bytes canónicos de la petición, y `<nombre>.sig`.
- El texto «SÍ PÚBLICO» desaparece como requisito, porque no prueba nada. El gesto humano es la firma.
- Sin ninguna clave registrada en `config/operator-grant-signers` de `origin/main`, `--authorize` lo explica, enlaza el alta de la clave (`autonomous-safety-merge-grant-reference.md` § Alta de la clave) y el suelo D, y sale con 1. No se crea nada.

### R2 — Verificador único

`scripts/lib/project_authz.py` es el único sitio donde se decide si un nombre está autorizado. Lo invocan todos los consumidores con `python3 -I` y un PATH fijo de sistema, como el verificador de grants. Se llama así: `project_authz.py allowed <nombre> --repo-root <raíz>`, y devuelve 0 si está permitido, 1 si no y 2 si no se puede evaluar.

Un nombre está **permitido** si se cumple una de estas dos condiciones:

- **(a) Ya es público.** Está en la whitelist del `.gitignore` leída con `git cat-file blob refs/remotes/origin/main:.gitignore`. La whitelist se normaliza por el primer segmento: `!projects/savia-vaults/package-lock.json` cuenta como el proyecto `savia-vaults`. La copia de trabajo y `HEAD` no cuentan.
- **(b) Tiene una autorización firmada válida.** Para eso, `config/project-authorizations/<nombre>.json` y su `.sig` deben cumplir todo esto:
  - el JSON está en forma canónica (el verificador lo regenera y compara byte a byte);
  - `project` es igual al nombre pedido, sin prefijos ni diferencias de mayúsculas;
  - `repo` es igual al remoto `origin` actual;
  - `ssh-keygen -Y verify` con `-n savia-project-publish` y la identidad `grantor` es válido contra el fichero de firmantes **de `origin/main`**;
  - el `nonce` no figura en `config/project-authorizations/REVOKED`, ni en `origin/main` ni en la copia de trabajo: basta con que esté en uno de los dos para que quede revocado.

Cualquier fallo da «no permitido»: herramienta ausente (`git`, `ssh-keygen`), sin `origin/main`, JSON no canónico o firma de otro namespace. Una firma de grant de merge (namespace `savia-operator-grant`) no vale como autorización de publicación.

### R3 — Consumidores

| Consumidor | Hoy | Con SE-491 |
|---|---|---|
| `protect-project-privacy.sh --hook` (pre-commit), verificación 1: línea nueva en `.gitignore` | Busca el nombre en el fichero editable | Solo (b): sin autorización firmada, se bloquea |
| `protect-project-privacy.sh --hook`, verificación 2: ficheros en `projects/<x>/` | Whitelist de la copia de trabajo | (a) o (b) |
| `protect-project-privacy.sh --check` | Lista las líneas del fichero | Lista la whitelist de main y las autorizaciones, con su estado: válida, no válida (y el motivo) o revocada |
| `protect-project-privacy.sh --ci --base <sha>` (nuevo) | — | Igual que `--hook`, sobre el diff `base...HEAD` de la PR. Los firmantes y `REVOKED` se leen de `base` |
| `block-gitignored-references.sh` (Claude Code) | Whitelist de la copia de trabajo, sin autorizaciones | Cada `projects/<x>/` del contenido pasa por el verificador con la raíz del repo **del fichero editado** (el criterio de la PR #1444) |
| `block-gitignored-references.ts` (OpenCode) | Sin regla en main; la PR #1444 lee el fichero editable | Llama al mismo verificador con `execFile`. No reimplementa la lógica en TS, para que los dos ports no diverjan |
| `block-project-whitelist.sh` | Bloquea toda línea nueva | Por cada línea nueva que detecta `gitignore-whitelist-delta.py`, permite si (b). Si no, bloquea con el mensaje de R1. `!/projects/x/` y las variantes con espacios se normalizan antes |
| `block-project-whitelist.ts` (OpenCode, nuevo) | No existe: en OpenCode nada frena la línea | Port que pasa el mismo JSON a `gitignore-whitelist-delta.py` y al verificador. Misma decisión que el bash |
| `scripts/risk-tier.py` | Clasifica por rutas; `.gitignore` no eleva el tier | `.gitignore`, `config/project-authorizations/` y `.githooks/` pasan a rutas de gobernanza (tier 4) |

La CI ejecuta `--ci` en el job obligatorio «Validate workspace». Es la frontera real: los hooks locales se pueden esquivar, y el ref `origin/main` local lo puede mover un agente (`git update-ref`). En la CI, `base` lo fija GitHub.

### R4 — Escrituras por Bash sobre `.gitignore`

No se intenta detectar las órdenes de escritura por su texto. Un regex sobre `sed`, `tee`, `>>`, `python -c`, `cp` o `git checkout` siempre deja huecos de FORMA. El hueco se cierra por dos lados:

1. **La whitelist local ya no concede nada.** Con R2(a), una línea añadida por Bash no amplía lo que permiten `block-gitignored-references` ni la verificación 2. Su único efecto posible es publicar al hacer commit, y eso lo paran el pre-commit y la CI.
2. **Aviso inmediato tras cada orden Bash.** Un hook PostToolUse sobre `Bash` (`.claude/hooks/gitignore-whitelist-drift.sh`) evalúa el `.gitignore` **resultante**, no la orden. Solo actúa si su `mtime` o su hash cambió desde la última evaluación, con la caché en el directorio de sesión. Usa el mismo `gitignore-whitelist-delta.py` contra la whitelist de `origin/main`. Si hay una línea nueva sin (b), sale con 2 y un mensaje que pide deshacerla, para que el modelo lo vea en el mismo turno. No revierte nada por su cuenta. La entrada llega por stdin (JSON).

### R5 — Migración de las líneas actuales

- Los 10 nombres de la whitelist de `origin/main` en el commit de corte pasan a «ya públicos» por R2(a), sin firma. Son estos: `proyecto-alpha`, `sala-reservas`, `savia-monitor`, `savia-web`, `savia-mobile-android`, `savia-vaults`, `savia-sonora` y `proyecto-beta`, más los ficheros sueltos `README.md` y `PROJECT_TEMPLATE.md`, que no son proyectos. Ya son públicos y firmarlos no protege nada.
- `claude-code-templates` estaba autorizado pero no publicado. No se migra, porque su autorización nunca tuvo firma. Si la operadora lo quiere publicar, lo firma con R1. La PR de implementación lo menciona en su body.
- `savia-vaults/package-lock.json` desaparece como autorización: R2(a) lo cubre con la normalización por el primer segmento.
- `.claude/.project-authorizations` se borra con `git rm` y pasa a `.gitignore`. Ningún consumidor lo vuelve a leer. Un test lo crea con un nombre no autorizado y comprueba que sigue bloqueado.
- Las líneas duplicadas de la whitelist (`sala-reservas`, `savia-mobile-android`, `savia-web` y `savia-monitor` aparecen dos veces) se deduplican en la misma PR. Es solo limpieza y no cambia qué es público.

### R6 — Cualquier operador

- **Instalación nueva, sin `~/.savia`:** funciona desde el clon. La whitelist de main y las autorizaciones firmadas vienen en el repo; no hace falta estado local.
- **Fork u otra organización:** cada repo tiene su propio fichero de firmantes. Una autorización de otro repo falla por `repo` aunque la firma sea válida.
- **Varios operadores:** el fichero de firmantes admite varias identidades, cada una con `namespaces="savia-operator-grant,savia-project-publish"` o solo una de las dos. Una identidad sin `savia-project-publish` no puede autorizar publicaciones.
- **Sin ninguna clave registrada:** (b) no existe y los agentes no pueden añadir whitelists. La persona puede publicar editando a mano y abriendo una PR, que `risk-tier.py` clasifica como tier 4 porque toca `.gitignore` (suelo D). El pre-commit le avisa y la CI exige la revisión humana.
- **Sin remoto `origin`** (repo recién creado con `git init`): (a) queda vacío y (b) falla por `repo`. Todo se bloquea, con un mensaje que lo explica.

## Amenazas y riesgos residuales

| Amenaza | Resultado |
|---|---|
| Un agente escribe la autorización a mano | Falla la firma (R2b) |
| Un agente copia una autorización válida de otro proyecto o de otro repo | Falla por `project` o por `repo` |
| Un agente restaura del historial una autorización revocada | Falla por `REVOKED`. Quitar un nonce de `REVOKED` necesita una PR fusionada |
| Un agente pasa «SÍ PÚBLICO» por una tubería | Ya no autoriza nada |
| Un agente edita `.gitignore` con `sed` | No concede nada a los guards (R4.1). Recibe el aviso PostToolUse y el commit se bloquea |
| Un agente mueve el `origin/main` local con `git update-ref` | **Residual local**: engaña a los hooks de ese equipo. La CI lo para, porque lee `base` de GitHub |
| Un agente añade su propia clave al fichero de firmantes | Necesita fusionar una PR que toca ese fichero, que es tier ≥ 3, y `push-pr.sh --merge` la rechaza |
| La clave privada sale del móvil | Fuera del alcance de esta spec. Es el mismo límite que tienen los grants de merge |

## Criterios de aceptación

- **AC-1 (sin fabricar):** con un fichero de firmantes de prueba, una autorización escrita a mano, una firmada con otra clave, una con namespace `savia-operator-grant`, una de otro `repo`, una con `project` que solo coincide por prefijo o por mayúsculas, una no canónica y una revocada dan exit 1 en `project_authz.py`. Una firmada correctamente da 0.
- **AC-2 (tubería):** `printf 'SÍ PÚBLICO\n' | protect-project-privacy.sh --authorize x` no crea nada en el repo y sale con 4 o con 1. Antes de la implementación, el mismo test falla, porque hoy esa orden autoriza.
- **AC-3 (consumidores):** para cada consumidor de R3, con las mismas fixtures, se comprueban tres casos: proyecto ya público en main (permitido), proyecto firmado (permitido) y proyecto no autorizado (bloqueado). Los ports bash y TS de cada guard devuelven lo mismo con la misma entrada, en un test que recorre ambos. `block-project-whitelist` (bash y TS) permite la línea firmada y bloquea `!/projects/y/` sin firma.
- **AC-4 (copia de trabajo sin autoridad):** una línea `!projects/y/` añadida con `sed` al `.gitignore` local no hace que `block-gitignored-references` permita `projects/y/`, y el pre-commit bloquea `git add -f projects/y/a.md`. Antes de la implementación, el primer caso falla.
- **AC-5 (Bash):** el PostToolUse sale con 2 tras `sed -i '$a !projects/y/' .gitignore` sin firma. Sale con 0 tras un Bash que no toca `.gitignore`, tras uno que quita una línea y tras uno que añade una línea firmada. Con el `.gitignore` sin cambios no invoca a Python, lo que se comprueba con un contador en la fixture.
- **AC-6 (migración):** en el commit de corte, `--check` muestra los 8 proyectos públicos como «ya públicos», sin avisos, y `claude-code-templates` como no autorizado. Un `.claude/.project-authorizations` recreado con `y` no permite `y` en ningún consumidor.
- **AC-7 (CI):** `--ci --base <sha>` bloquea una PR de fixture que añade `!projects/y/` sin firma y permite la misma PR con firma válida. Lee los firmantes de `base`, y una PR que añade su propia clave y una firma hecha con ella sigue bloqueada.
- **AC-8 (multioperador):** fixtures con dos operadores (A y B) y dos repos (R1 y R2):
  - A está registrada en R1 y su firma vale allí;
  - la firma de A copiada a R2, donde solo está B, no vale;
  - si B tiene solo `savia-operator-grant`, no puede autorizar publicaciones;
  - en una instalación sin firmantes, los agentes quedan bloqueados, el suelo D se explica y `--authorize` sale con 1;
  - con `HOME` vacío (sin `~/.savia`), (a) y (b) funcionan desde el clon;
  - sin remoto, todo se bloquea.
- **AC-9 (fail-closed):** sin `ssh-keygen`, sin `git`, con `origin/main` ausente o con el JSON corrupto, ningún consumidor permite un proyecto nuevo. Los ya públicos en main siguen permitidos mientras `git` y `origin/main` existan.
- **AC-10 (tests que pueden fallar):** cada test nuevo se ejecuta contra el código anterior o con la aserción mutada, y falla. El body de la PR lo documenta con la cuenta de fallos antes y después (SE-456).

## Fuera de alcance

- Detectar escrituras por Bash a partir del texto de la orden (R4 explica por qué no).
- Sacar la clave del móvil o cambiar el alta de claves de SE-343.
- La vía de aprobación por fusión de PR en un repo privado (SE-488). Si se aprueba, puede ser un segundo backend de (b), en otra spec.
- Publicar proyectos de cliente: sigue prohibido, con o sin firma.

## Plan de implementación

Una sola PR, tier 4, con revisión humana explícita. Toca hooks sensibles (`.claude/hooks/*`), que un agente no puede editar sin permiso de la operadora: o los aplica ella, o concede un permiso puntual para esa PR. Si la PR #1444 se fusiona antes, su consulta del fichero editable se sustituye por el verificador. Si no, esta PR porta la regla a TS con el verificador.

1. `scripts/lib/project_authz.py` y sus tests (AC-1, AC-8, AC-9).
2. `protect-project-privacy.sh`: `--authorize` en dos pasos, `--check`, `--hook` y `--ci` (AC-2, AC-4, AC-6, AC-7).
3. Los hooks bash, el port TS de `block-gitignored-references` y el port TS nuevo de `block-project-whitelist`; `risk-tier.py` (AC-3).
4. PostToolUse `gitignore-whitelist-drift.sh` y su registro en `.claude/settings.json` (AC-5).
5. Migración: `git rm`, `.gitignore`, deduplicación y paso de CI en «Validate workspace» (AC-6, AC-7).
6. Documentación: `zero-project-leakage.md` y el alta de clave con el namespace nuevo en `autonomous-safety-merge-grant-reference.md`.

## Rollback

Revertir la PR devuelve el fichero de texto y los hooks actuales. Las autorizaciones firmadas que ya existan quedan como ficheros inertes, que nadie lee.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Verificador | `scripts/lib/project_authz.py` | el mismo script |
| Referencias a proyectos | `.claude/hooks/block-gitignored-references.sh` (PreToolUse Edit/Write) | `.opencode/plugins/guards/block-gitignored-references.ts`, que llama al verificador con `execFile` |
| Whitelist en `.gitignore` | `.claude/hooks/block-project-whitelist.sh` (PreToolUse Edit/Write) | `.opencode/plugins/guards/block-project-whitelist.ts` (nuevo), que delega en `gitignore-whitelist-delta.py` y en el verificador |
| Deriva tras Bash | `.claude/hooks/gitignore-whitelist-drift.sh` (PostToolUse Bash) | guard nuevo en `tool.execute.after` para `bash` que ejecuta el mismo script |
| Commit y CI | `.githooks/pre-commit` y job «Validate workspace» | lo mismo: no dependen del frontend |

### Verification protocol

- [ ] Test que da la misma entrada a los guards bash y TS y espera el mismo veredicto en los 3 casos de AC-3.
- [ ] El verificador se invoca con `python3 -I` desde ambos frontends; ningún port lo reimplementa.
- [ ] El PostToolUse se dispara en los dos frontends con la misma fixture de `sed`.

### Portability classification

- [x] **DUAL_BINDING**: la lógica vive en un script común. Cada frontend solo aporta el registro del hook.
