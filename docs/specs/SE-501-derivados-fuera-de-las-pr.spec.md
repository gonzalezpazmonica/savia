---
status: APPROVED
approved_at: 2026-11-03
approved_by: "operadora, pregunta interactiva 2026-11-03 (Aprobada, implementa); la aprobación se formaliza al fusionar esta PR (SE-488)"
priority: P1
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L4
related_specs: [SE-053, SE-397, SE-407, SE-426, SE-433, SE-453, SE-487, SE-500]
origin: "Inoperatividad declarada por la operadora el 2026-11-03: con 12 PR abiertas, cada merge desalinea al resto porque todas reescriben la firma de confidencialidad, el SAM y el manifiesto de reglas. Encargo de la orquestadora, plan intensivo. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-501 — Derivados fuera de las PR: firma de confidencialidad, SAM y manifiesto de reglas generados en main

## Problema (verificado en origin/main 7a648ab7d, 2026-11-03)

Cuatro artefactos generados se versionan y cada PR los reescribe. Dos PR cualesquiera chocan en ellos aunque no compartan una sola línea de código.

| Artefacto | Commits de `main` que lo cambian en 7 días | Por qué cambia en cada PR |
|---|---|---|
| `.confidentiality-signature` | 63 (los 63 commits first-parent del periodo) | `get_diff_hash` (`scripts/confidentiality-sign.sh:13-22`) hashea el árbol completo de `HEAD`. Cualquier commit cambia el hash. Además la CI exige que la PR lo incluya (`ci.yml`, paso «Gate: PR created via /pr-plan», líneas 116-131) |
| `.scm/sam.json` y el resto de `.scm/` generado | 27 | Hashes agregados: `content_hash` de `registry.json`, `hash:` de `INDEX.scm`, `model_revision` del SAM. Un recurso nuevo o editado los cambia |
| `docs/rules/domain/rule-manifest.json` | 19 | Recuentos de reglas y la clave `generated` con la hora (`scripts/rule-manifest-generate.sh:76`) |
| `docs/rules/INDEX.md` | 8 | Fecha en la línea 1 y una fila por regla (`scripts/rules-index-generate.sh:110`) |

Fuente: `git log --since='7 days ago' origin/main -- <ruta>` y `git log --first-parent`. Había 12 PR abiertas. `main` tiene protección clásica con `strict: true` y `enforce_admins: true` (`gh api repos/…/branches/main/protection`), así que cada merge obliga a actualizar las demás y cada actualización vuelve a chocar en estos ficheros. Hoy lo absorben cinco mecanismos de reparación: `_resolve_signature_conflict` en G4 de pr-plan, `pr-rebase.sh`, `resolve-pr-conflicts.sh`, `auto-rebase-open-prs.yml` y `resync` de `merge-sprint.sh`, con `DERIVED_RE` (`scripts/merge-sprint.sh:235`). Cada uno regenera y vuelve a firmar en la rama de la PR. La operadora lo ha declarado inoperativo.

### Hallazgos de la lectura (los resuelve esta spec)

1. **La firma no prueba que el escaneo pasara.** `confidentiality-sign.sh sign` no ejecuta `confidentiality-scan.sh`: firma el árbol que tenga delante. Lo que prueba la firma es que alguien con la clave HMAC firmó ese árbol. El escaneo es un paso aparte de pr-plan (G7) y de la CI.
2. **Los checks de confidencialidad no son obligatorios.** Los contextos requeridos de `main` son `Validate workspace`, `PR Guardian`, `Lint Markdown` y `BATS Hook Tests`. Ni `Verify Audit Signature` ni `PII & Confidentiality Scan (PR)` (`confidentiality-gate.yml`) están entre ellos.
3. **La PR escanea con su propio escáner.** En `pull_request` la CI ejecuta `scripts/confidentiality-scan.sh` y `generate-blocklist.sh` de la rama de la PR. Una PR puede modificar el escáner para no detectarse a sí misma.
4. **La clave HMAC llega a jobs de PR.** `confidentiality-gate.yml` (job `signature-check`, evento `pull_request`) recibe `secrets.CONFIDENTIALITY_HMAC_KEY`. Los secretos se exponen a los workflows de PR de ramas del mismo repositorio, y una rama `agent/*` puede añadir un workflow que firme cualquier árbol.
5. **Un commit de bot no puede entrar en `main` sin una autoridad nueva.** `PR Guardian` solo se ejecuta en `pull_request`. Un commit que no venga de una PR nunca tiene ese contexto requerido, así que un workflow que quiera escribir en `main` necesita una de dos cosas: un actor con bypass de la protección, o abrir una PR y fusionarla sin grant.

## Objetivo

Que ninguna PR contenga estos cuatro derivados. Dos PR sin código común deben fusionarse en cualquier orden sin conflicto y sin re-firma. A la vez, la garantía de confidencialidad tiene que salir más fuerte que hoy: escaneo obligatorio y bloqueante en cada PR, hecho con el código de la base, y una prueba por commit de que el contenido de `main` pasó la auditoría.

## Alcance: lista cerrada de derivados (D)

- `.confidentiality-signature`.
- Los artefactos generados de `.scm/`: `SCM_GENERATED_FILES` y `SCM_GENERATED_DIRS` de `scripts/risk-tier.py` (`sam.json`, `registry.json`, `resources.json`, `INDEX.scm`, `views/`, `reports/`, `categories/`).
- `docs/rules/INDEX.md`.
- `docs/rules/domain/rule-manifest.json`.

**No son D** y siguen versionados y editados a mano: `.scm/sam-declarations.json`, `.scm/sam-runtime-declarations.json`, `.scm/sam-verification-declarations.json`, `.scm/sam.schema.json` y `.scm/runtime-surface/**` (SE-433 §2.6: «las declaraciones de `.scm/` editadas a mano no son derivados»). Tampoco `docs/propuestas/ROADMAP-CURRENT.md` (7 cambios en 7 días) ni `docs/propuestas/INDEX.md` (1), que SE-500 S2 trata como derivados y que S1 ya reduce. Si hace falta, se añaden a D en otra spec con su medición.

## Diseño en la PR (común a las dos opciones)

1. **La PR no versiona D.** Un gate nuevo, `G20 Derivados fuera de la PR` en pr-plan y paso `Derived paths absent` en la CI, falla si `git diff --name-only <merge-base>..HEAD` contiene una ruta de D. La lista D vive en un único fichero, `scripts/derived-paths.txt`, que leen el gate, `merge-sprint.sh` y `risk-tier.py`. La comparación de rutas es exacta o por prefijo de directorio, nunca por regex abierta. Pista de reparación: `bash scripts/derived-drop.sh`, que crea un commit que devuelve D al estado de `origin/main` (o lo quita del índice tras la migración).
2. **La CI regenera y verifica sin versionar.** En el commit de merge de la PR, la CI ejecuta los cuatro generadores. Comprueba que terminan con 0, que su salida pasa su validación interna (`sam.py check` sobre lo recién generado, JSON válido con las claves obligatorias del manifiesto, una fila por regla en `INDEX.md`) y que son deterministas: dos ejecuciones dan la misma salida en su forma canónica (sin la marca de tiempo, como fija SE-500 S2). El paso «Generated artifacts fresh» (`validate-ci-local.sh --fresh-only`) cambia de semántica en esas tres filas: pasa de «lo commiteado coincide con lo regenerado» a «la generación funciona y es determinista». Si falta un generador o la herramienta, falla (fail-closed). Así una PR que rompe un generador se sigue parando antes del merge.
3. **El escaneo de confidencialidad sobre el diff de la PR es obligatorio y bloqueante.**
   - El escáner y la blocklist se toman del commit **base** de la PR, extraídos a un directorio aparte. El diff se toma de la PR. Una PR que modifica el escáner no se audita con su versión modificada (hallazgo 3).
   - El veredicto sale de la línea `gate-result:` de SE-453: solo `clean` da PASS. `findings`, `unknown`, salida sin esa línea o código de salida ≠ 0 dan FAIL.
   - El job se llama `Confidentiality scan (PR)` y la operadora lo añade a los contextos requeridos de `main` (hallazgo 2). Es una acción suya en GitHub y figura en la migración.
   - Ningún job disparado por `pull_request` recibe `CONFIDENTIALITY_HMAC_KEY` (hallazgo 4).
4. **Se retira el indicio «la PR trae firma».** El paso de `ci.yml` que exige `.confidentiality-signature` en la PR era un indicio débil de que se había ejecutado pr-plan: cualquiera con la clave puede firmar sin escanear (hallazgo 1). Lo sustituyen los checks reales del punto 3 y del punto 2, ejecutados por la CI.

## Tras el merge: dos opciones

### Opción A — Un workflow en `main` regenera D y lo commitea

`derived-main.yml` en `push` a `main` regenera D con el código del commit fusionado, escanea el árbol completo, firma y commitea un solo commit `chore(derived): …` que solo toca rutas de D. `paths-ignore: D` evita el bucle: un push que solo cambia D no dispara el workflow. Además la generación tiene que ser un punto fijo (regenerar sobre el commit del bot no cambia nada). El push es sin forzar: si `main` se ha movido, falla y el siguiente run lo rehace.

Para escribir en `main` necesita una autoridad que hoy no existe (hallazgo 5):

- **A1, bypass:** un ruleset con una GitHub App como actor de bypass. El bypass de un ruleset es por actor: la App salta todas las reglas de ese ruleset, sin restricción por ruta, así que podría empujar cualquier contenido. La credencial tendría que vivir en un *environment* limitado a la rama `main`, para que ningún workflow de PR pueda leerla. La garantía de «solo rutas de D» la daría el propio código del workflow, revisado como tier 4, y no GitHub.
- **A2, PR del bot:** el bot abre una PR (con token de App, porque las PR creadas con `GITHUB_TOKEN` no disparan workflows) y la fusiona sola. Eso es un merge sin grant: choca con la Regla 8 y con SE-343.

Las dos variantes piden a la operadora una autorización permanente de escritura en `main` para un actor no humano. Mientras el commit del bot no llega, `main` tiene derivados atrasados. Y cada commit del bot desactualiza, por `strict`, todas las PR abiertas: sin conflicto, pero con una CI más por PR.

### Opción B — D deja de versionarse y se genera bajo demanda (recomendada)

- D pasa a `.gitignore` y la PR de migración lo quita del índice (`git rm --cached`). No hay commit de bot ni escritura en `main`.
- `scripts/derived.sh ensure [--only scm|rules]` genera D en el árbol de trabajo si falta o está desfasado. La clave de frescura se guarda en `.scm/.derived-stamp` y en `docs/rules/.derived-stamp` (ignorados): `sha256(HEAD^{tree} + git status --porcelain=v1 -z de los ficheros de entrada + blobs de los generadores)`. Con la clave igual, la llamada no hace nada y tarda menos de 1 s. Medido en la máquina de la operadora: `generate-capability-map.py` 0,3 s, `sam.py generate` 14,3 s, manifiesto e índice de reglas 1,9 s.
- **Lectores.** Cada lector de D llama antes a `derived.sh ensure`, o falla con un mensaje que nombra esa orden si D falta. Hoy los lectores son 32 scripts en `scripts/`, 2 en `scripts/dual-cli/`, 3 hooks, 2 ficheros de `config/` y 2 workflows, más 37 tests (inventario con `grep -rlE '\.scm/|rule-manifest\.json|rules/INDEX\.md'`). `session-init.sh` ya regenera `.scm` en segundo plano: sigue igual y no bloquea el arranque (arranque blindado). Un lector que no esté en el inventario hace fallar un test (AC-11).
- **La firma pasa a ser un hecho de la CI por commit.** `confidentiality-main.yml`, en `push` a `main`, ejecuta `confidentiality-scan.sh --full-repo` con la blocklist dinámica y con el código del propio commit fusionado (38,5 s medido en local), con `permissions: contents: read` y sin secretos. La prueba de que el commit `X` de `main` pasó la auditoría es esta: existe una ejecución de `.github/workflows/confidentiality-main.yml` con `event=push`, `head_branch=main`, `head_sha=X` y `conclusion=success`. La comprueba `scripts/confidentiality-main-verify.sh X` con `gh api`. No se usa un *commit status*: cualquier workflow de PR con `statuses: write` podría falsificarlo sobre cualquier SHA antes de que nadie lo revise. Una ejecución con `event=push` en `main` no la puede crear una PR.
- La clave HMAC y `confidentiality-sign.sh` se retiran del flujo de PR. El script sigue existiendo para verificar firmas históricas y se marca como tal.

### Comparación

| Criterio | A (commit de bot en `main`) | B (no versionar) |
|---|---|---|
| Conflictos por D entre PR | 0 | 0 |
| Autoridad nueva | Escritura permanente en `main` para una App (A1) o merge sin grant (A2) | Ninguna. El workflow nuevo solo lee |
| Ajustes de GitHub que hace la operadora | App, ruleset con bypass, environment y check requerido | Check requerido |
| Superficie tier 4 | Un workflow que escribe en `main` con credencial | Un workflow de solo lectura |
| Bucle y punto fijo | Hay que garantizarlos (`paths-ignore`, regeneración idempotente; el SAM registra el último commit de cada fuente) | No existen |
| Ventana con `main` desfasado | Desde el merge hasta el commit del bot | No hay: cada clon genera lo suyo |
| CI extra por merge | Una en `main` y otra en cada PR abierta (por `strict`) | Una en `main`, de solo lectura |
| Coste de migración | Bajo en los lectores (D sigue en el árbol) y alto en el workflow y la seguridad | Unos 41 ficheros lectores y 37 tests que revisar |
| Coste en uso | Ninguno | Primer arranque tras clonar o cambiar de rama: hasta unos 16 s de generación (en segundo plano en `session-init`) |
| Lo que se pierde | Nada | El historial git de D y su vista en la web de GitHub. Para el diff del SAM que hoy se ve en la PR, la CI publica `sam.json` regenerado como artefacto del run y un resumen en `$GITHUB_STEP_SUMMARY` |
| Verificar la firma sin red | Sí, con la clave | No: necesita la API de GitHub. Para el flujo no hace falta, porque nadie verifica la firma de `main` sin red |

**Recomendación: B.** Sus costes son de trabajo (migrar lectores) y de unos segundos de generación local. Los de A son de autoridad y de seguridad: una credencial con escritura en `main` en manos de una máquina, justo lo que autonomous-safety y la Regla 8 reservan a la persona. Si la operadora elige A, se implementa A1 con los AC del bloque «Si se elige A», y aprobar esta spec con A equivale a conceder esa autorización permanente, que queda registrada en el campo `approval` del registro.

## Garantías y modelo de amenazas

### Invariantes

- **I1.** Ningún commit entra en `main` sin que `Confidentiality scan (PR)` haya pasado sobre su diff con el escáner de la base. La protección de `main` lo impone (check requerido y `strict`). Con `enforce_admins`, tampoco un push directo lo evita, porque el commit no tendría el contexto requerido.
- **I2.** Cada commit de `main` tiene una ejecución identificable de `confidentiality-main.yml` sobre su árbol completo. Si el escaneo completo falla (por ejemplo, porque la blocklist creció después del merge), la ejecución queda roja, a la vista, y `confidentiality-main-verify.sh` devuelve ≠ 0.
- **I3.** Ningún job disparado por un evento de PR tiene secretos de firma ni permisos de escritura sobre contenido o estados.

### Amenazas

| Amenaza | Control |
|---|---|
| Una PR modifica el escáner o la blocklist para colar un dato | El escaneo de PR usa el escáner de la base (AC-3). Cambiar el escáner es tier 4 y lo revisa la operadora |
| Una PR modifica el workflow de escaneo (en `pull_request` corre la versión de la PR) | Rutas `.github/workflows/` en tier 4 (`GOVERNANCE_PREFIXES`) con revisión humana antes del merge (SE-362). Riesgo residual declarado: la protección por nombre de check no distingue un job vaciado con el mismo nombre. Lo detecta I2 tras el merge, no antes |
| Una PR falsifica la prueba de `main` | La prueba es una ejecución con `event=push` en `main` y la ruta exacta del workflow. Un run de PR tiene `event=pull_request`. Un estado o check publicado por la PR no cuenta (AC-7) |
| Una PR lee la clave HMAC | En la opción B no queda ningún job de PR con el secreto (AC-15). En la A, la credencial vive en un environment limitado a `main` |
| `pull_request_target` | No se usa. Un test estático falla si cualquier workflow lo declara junto a un checkout de la ref de la PR (AC-6) |
| La API de GitHub no responde al verificar | `confidentiality-main-verify.sh` falla cerrado (≠ 0) |
| D generado localmente se cuela en un commit | En B, D está en `.gitignore`. Si alguien lo fuerza con `git add -f`, G20 y el paso de la CI fallan (AC-1) |
| Divergencia entre lo que ve el agente y `main` | D local se genera desde el árbol del agente, que es el que debe ver. No hay copia «oficial» que pueda divergir |

## Migración

1. **S1, preparación (sin cambio de comportamiento para las PR abiertas):** `derived-paths.txt`, `derived.sh ensure`, `derived-drop.sh`, `confidentiality-main.yml`, `confidentiality-main-verify.sh` y el escaneo de PR con el escáner de la base. Los lectores pasan a llamar a `ensure`. G20 y su paso de CI entran solo en modo aviso. Es tier 4 (toca `.github/workflows/`).
2. **Acción de la operadora en GitHub:** añadir `Confidentiality scan (PR)` a los contextos requeridos de `main`. `scripts/derived-migration-check.sh` (solo lectura, `gh api`) confirma que está y que ningún workflow de PR recibe `CONFIDENTIALITY_HMAC_KEY`.
3. **S2, corte (una PR, tier 4):** `git rm --cached` de D y alta en `.gitignore`. G20 pasa a bloquear. Se retiran el paso de firma de `ci.yml`, el job `signature-check` y el secreto de `confidentiality-gate.yml`, `_resolve_signature_conflict` de G4, y la firma de `push-pr.sh`, `pr-rebase.sh`, `resolve-pr-conflicts.sh`, `gate-post-receive.sh`, `auto-rebase-open-prs.yml` y `changelog-consolidate.yml`. `DERIVED_RE` de `merge-sprint.sh` queda sin D.
4. **PR abiertas en el corte:** cada una ejecuta `bash scripts/derived-drop.sh`, que deja un commit que borra D del diff de la PR. Desde ahí se fusionan sin conflictos de D. `merge-sprint.sh resync` hace lo mismo de forma automática, porque es un cambio mecánico de rutas de D. La equivalencia del head acepta ese commit solo si borra rutas de D y nada más.
5. **Encargo común de los workers:** los pasos 3 («`sam.py generate` y commit de `.scm`») y 5 («`confidentiality-sign.sh sign` y commit») del cierre de PR se sustituyen por `bash scripts/derived.sh ensure` (sin commit) y `bash scripts/confidentiality-scan.sh --pr` (sin firma). Esto lo cambia la orquestadora en su fuente, no esta spec.

### Impacto

- **pr-plan:** G4 deja de resolver la firma. G7 sigue igual, porque es el escaneo. G20 es nuevo. G5b y G10 siguen, con la nueva semántica de frescura. G13 no cambia: D no figura entre los ficheros de la PR.
- **Gates de la CI:** «Generated artifacts fresh» cambia de semántica en tres filas (Diseño 2). `ci-extended-checks.sh` deja de comparar `.scm/INDEX.scm` y `sam.json` con lo commiteado y valida la generación.
- **SE-433:** §2.6 pierde D como derivados admitidos. Si `H1` difiere de `T` en una ruta de D, el head **no** es equivalente (fail-closed), salvo el commit de `derived-drop.sh` descrito en el punto 4. D9 (re-auditoría de la firma) se sustituye por I1 e I2.
- **SE-500 S2 (PR #1469 abierta):** la tabla de comparación canónica pierde las filas de `.scm/`, `docs/rules/INDEX.md`, `rule-manifest.json` y `.confidentiality-signature`, y AC-12c (re-firma) deja de aplicar. Quedan `ROADMAP-CURRENT.md` y `docs/propuestas/INDEX.md`. `resync` deja de ejecutar generadores y de firmar para D: el escaneo `--pr` que hace hoy se conserva, porque solo lee. Ninguna de las dos specs bloquea a la otra. La que se fusione después ajusta `DERIVED_RE` y la tabla en su PR.
- **`risk-tier.py`:** `SCM_GENERATED_*` se lee de `derived-paths.txt`.

## Criterios de aceptación

### PR

- [ ] AC-1: negativo: una PR cuyo diff contiene `.scm/sam.json`, `.confidentiality-signature`, `docs/rules/INDEX.md` o `rule-manifest.json` hace que G20 y el paso `Derived paths absent` den FAIL y nombren la ruta. Positivo: una PR sin D da PASS. Límite: una PR que cambia `.scm/sam-declarations.json` o `.scm/runtime-surface/…` da PASS, y una ruta parecida que no es D (`docs/rules/INDEX.md.bak`) también da PASS, porque la comparación es exacta o por prefijo de directorio.
- [ ] AC-2: negativo: si un generador termina con ≠ 0, si da dos salidas canónicas distintas en dos ejecuciones o si falta, el paso de frescura da FAIL. Positivo: los cuatro generadores sobre el árbol actual dan PASS sin que haya D commiteado.
- [ ] AC-3: negativo: una PR que añade un dato bloqueado y modifica `confidentiality-scan.sh` o `generate-blocklist.sh` para excluirlo queda BLOCKED, porque el escaneo usa la base. El mismo test con el escáner de la PR pasa, lo que demuestra que el test puede fallar.
- [ ] AC-4: negativo: un escáner que termina sin línea `gate-result:`, con `unknown` o con `findings` da FAIL en `Confidentiality scan (PR)`. Solo `clean` da PASS. `derived-migration-check.sh`, con una respuesta simulada de `gh api` que no incluye ese contexto entre los requeridos, da FAIL.
- [ ] AC-5: dos ramas que cambian ficheros de código distintos y regeneran D en local se fusionan en cualquier orden con `git merge`, sin conflicto. El test falla con D versionado: es la reproducción del problema.

### `main`

- [ ] AC-6: test estático de workflows. `confidentiality-main.yml` tiene `permissions: contents: read` y nada más, no tiene `secrets.`, sus acciones van fijadas por SHA y se dispara solo con `push` a `main`. Negativos con YAML de prueba: añadir `contents: write`, `statuses: write`, un secreto o `pull_request_target` con checkout de `github.event.pull_request.head.sha` da FAIL.
- [ ] AC-7: `confidentiality-main-verify.sh X`, con `gh` simulado, da 0 solo si existe una ejecución de `.github/workflows/confidentiality-main.yml` con `event=push`, `head_branch=main`, `head_sha=X` y `conclusion=success`. Da ≠ 0 en cada uno de estos casos: evento `pull_request`, otro `head_sha`, `conclusion=failure`, otra ruta de workflow con el mismo nombre visible, un commit status `success` sin ejecución, API caída o respuesta no JSON.
- [ ] AC-8: negativo: un árbol de prueba con un dato bloqueado hace que el job de escaneo completo termine con ≠ 0.

### Generación bajo demanda (opción B)

- [ ] AC-9: en un clon limpio, `derived.sh ensure` genera D. La segunda llamada con el mismo árbol no ejecuta generadores (lo prueba un generador espía) y tarda menos de 1 s. Tras editar un fichero de entrada, regenera. La salida es igual, en forma canónica, a la de los generadores ejecutados a mano.
- [ ] AC-10: tras `ensure`, `git status --porcelain` está vacío. El test falla mientras D esté versionado.
- [ ] AC-11: el inventario de lectores de D (grep del test) coincide con la lista declarada en el test. Cada lector llama a `ensure` o, si D falta y `ensure` falla, termina con ≠ 0 y con un mensaje que nombra `derived.sh ensure`. Negativo: un script nuevo que lee `.scm/registry.json` sin estar en la lista hace fallar el test. `session-init.sh`, con D ausente, termina en el mismo tiempo que hoy (no espera a la generación).

### Migración

- [ ] AC-12: tras el corte, ningún script ni workflow escribe `.confidentiality-signature` (test por grep sobre `scripts/` y `.github/workflows/`), `ci.yml` no exige la firma en la PR y G4 no tiene `_resolve_signature_conflict`.
- [ ] AC-13: `merge-sprint.sh`: si `H1` difiere de `T` en una ruta de D, el head es no equivalente. Si `H1` es `T` más un commit de `derived-drop.sh` que solo borra rutas de D, es equivalente. Si ese commit borra además otra ruta, no lo es. `resync` no ejecuta generadores ni firma. Las aserciones de `tests/test-merge-sprint.bats` que codifican D como derivado regenerable se sustituyen por estos casos, y la PR las enumera.
- [ ] AC-14: una PR abierta con D en su diff, tras `derived-drop.sh`, se fusiona con el `main` posterior al corte sin conflictos (test con ramas).
- [ ] AC-15: negativo: ningún job disparado por `pull_request` o `pull_request_target` referencia `CONFIDENTIALITY_HMAC_KEY` (test estático sobre todos los workflows). Un YAML de prueba que lo hace da FAIL.
- [ ] AC-16 (medición, 7 días tras el corte): 0 commits de `main` que toquen D y 0 aparcamientos de merge-sprint con D entre los ficheros en conflicto (ledger). Línea base: 63, 27, 19 y 8 commits.

### Si se elige A (sustituye AC-9 a AC-11)

- [ ] AC-A1: punto fijo. Regenerar D sobre el commit del bot no produce diff. Lo comprueba un test que regenera dos veces y exige un diff vacío.
- [ ] AC-A2: negativo: si la regeneración produce un cambio fuera de D, el workflow sale con ≠ 0 sin empujar.
- [ ] AC-A3: un push que solo cambia D no dispara el workflow (`paths-ignore`), y el push del bot es sin forzar: con `main` movido, falla sin reintentar con fuerza.
- [ ] AC-A4: la credencial de escritura está en un environment con política de rama `main`. Negativo: un workflow de PR de prueba que la pide no la recibe.

## Esfuerzo estimado (opción B)

| Pieza | Esfuerzo | Quién |
|---|---|---|
| S1: scripts nuevos, escaneo con el escáner de la base, `confidentiality-main.yml`, tests AC-1 a AC-9 y AC-15 | 8-10 h | Un worker, PR tier 4 |
| S1: migración de los unos 41 lectores a `ensure` y AC-10 y AC-11 | 6-8 h | Un worker, misma PR o una segunda en serie |
| Acción en GitHub (check requerido) | 10 min | Operadora |
| S2: corte, retirada de la firma en 7 scripts y workflows, `merge-sprint.sh`, AC-12 a AC-14 | 4-6 h | Un worker, PR tier 4 |
| AC-16 | 7 días de observación | Orquestadora |

Con la opción A1 el esfuerzo de los lectores desaparece y aparecen la App, el ruleset y el environment (operadora) y el workflow de escritura con AC-A1 a AC-A4 (unas 6-8 h).

## Fuera de alcance

- `docs/propuestas/ROADMAP-CURRENT.md` y `docs/propuestas/INDEX.md` (ver Alcance).
- `CHANGELOG.md` y `CHANGELOG.d/` (SE-053 ya los resuelve). `changelog-consolidate.yml` solo pierde su paso de firma. Su `gh pr merge --auto` y su `push --force-with-lease` sobre `agent/changelog-consolidate` chocan con la Regla 8 y con autonomous-safety, pero se tratan en otra spec.
- Cambiar la protección de `main` más allá de añadir un contexto requerido.
- Firmas criptográficas fuera de GitHub (attestations, sigstore). Si la prueba por ejecución de I2 no basta, otra spec.

## Riesgos

| Riesgo | Mitigación |
|---|---|
| Un lector de D olvidado se rompe con D ausente | Inventario por test (AC-11) y fallo con mensaje explícito |
| Primer arranque más lento | `ensure` en segundo plano en `session-init`, con clave de frescura |
| La operadora no añade el check requerido y el escaneo de PR queda informativo | El corte (S2) solo se fusiona si `derived-migration-check.sh` da PASS |
| La PR de migración y SE-500 S2 se pisan en `merge-sprint.sh` | Se fusionan en serie. La segunda ajusta `DERIVED_RE` y la tabla (Impacto) |
| Prueba de `main` dependiente de la retención de ejecuciones de GitHub (90 días por defecto) | `confidentiality-main-verify.sh` informa «sin ejecución» como FAIL. La prueba que importa es la del commit actual de `main`, cuyo escaneo completo cubre todo el árbol, incluido el contenido de commits antiguos; un `workflow_dispatch` sobre `main` crea una ejecución nueva para su cabeza |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/derived.sh`, `derived-drop.sh`, `derived-paths.txt`, `confidentiality-main-verify.sh`, `derived-migration-check.sh` | Bash desde la sesión o la CI | Los mismos scripts |
| `scripts/pr-plan-gates.sh` (G20), `merge-sprint.sh`, `risk-tier.py`, `validate-ci-local.sh` | Bash y Python stdlib | Los mismos |
| `.claude/hooks/session-init.sh` y los otros 2 hooks lectores de D | Hook SessionStart | Plugin equivalente en `.opencode/plugins`, si lee D: llama a `derived.sh ensure` igual |
| `.github/workflows/confidentiality-main.yml`, `confidentiality-gate.yml`, `ci.yml` | CI, independiente del frontend | CI, independiente del frontend |

### Verification protocol

- [ ] Funciona en runtime OpenCode: los scripts no dependen del frontend y los lectores de D de `.opencode/` están en el inventario de AC-11
- [ ] Tests BATS y pytest cubren el único camino de ejecución
- [ ] No añade hooks nuevos: modifica hooks lectores existentes

### Portability classification

- [x] **PURE_BASH**: bash y Python stdlib; los workflows son de la CI y ningún binding depende del frontend.

## Aprobación

Las PR de implementación son tier 4: tocan `.github/workflows/`, el escaneo de confidencialidad y `scripts/merge-sprint.sh`. La revisa y la fusiona la operadora a mano, fuera de cualquier manifiesto de merge-sprint. Esta PR solo toca `docs/` y `risk-tier.py` la clasifica en tier 1, pero cambia una garantía de confidencialidad y de SE-433 §2.6: la operadora no la incluye en ningún manifiesto y la fusiona ella tras aprobarla. Ningún agente la fusiona. Al aprobar se elige la opción: B (recomendada) o A1, y A1 conlleva la autorización permanente descrita en la opción A.
