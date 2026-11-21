# HOLD entre cabezas equivalentes — tests de regresión

Encargo de TDD cruzado sobre `scripts/merge-sprint.sh` (SE-433), incidente
#1642. Base local: `origin/main`, commit `5c2603e8b`. Solo se añaden tests,
estas notas y el fragmento de changelog; no se cambia producción ni specs.

## Resultado medido

`bats --filter 'HOLD-head' tests/test-merge-sprint.bats`: **6 pasan, 4 fallan**
contra el ejecutor original. Los fallos son deliberados: fijan el contrato
exigido y quedan pendientes de la implementación de la otra programadora.
No se omiten tests ni se relajan aserciones para presentar una suite verde.

| Test nuevo (prefijo `HOLD-head`) | Hoy en main |
| --- | --- |
| plan: HOLD P1 en B, APPROVE en A equivalente | FALLA: B entra en el manifiesto |
| plan: HOLD en B intermedia entre APPROVE A y cabeza C | FALLA: C entra usando A |
| run: HOLD B registrado después del grant calculado sobre A | FALLA: B se fusiona |
| run: B y su HOLD aparecen después del grant | FALLA: B se fusiona |
| negativo: APPROVE A, B equivalente, sin HOLD | PASA: se fusiona B con su SHA |
| negativo: HOLD A, arreglo y APPROVE B | PASA: B entra y se fusiona |
| negativo: HOLD B, APPROVE C posterior y D equivalente | PASA: se usa C y se fusiona D |
| negativo: HOLD de otra PR sobre el mismo SHA | PASA: no bloquea esta PR |
| límite: HOLD tras el grant sobre el mismo SHA aprobado | PASA: PARK con motivo `revision`, sin intento de merge |
| contrato: VERDICT con `error=sin-revision` | PASA: registro rechazado, sin retención |

El plan debe excluir estructuralmente la PR y explicar la exclusión con una
línea `excluida PR <n>:` que mencione HOLD (sin fijar el resto del texto).
El run debe emitir `aparcado #<n>: revision`, registrar PARK/revision y no
invocar `gh pr merge`. El control sin HOLD comprueba que el merge usa B,
aunque el manifiesto conserve el SHA aprobado A.

## Contrato actual de `sin-revision`

`review-register` exige coincidencia completa de la primera línea VERDICT.
Un sufijo `error=sin-revision` devuelve **3** y
`primera línea sin gramática VERDICT válida`; no añade ningún registro.
El test comprueba que `reviews.jsonl` conserva exactamente su hash y que
el APPROVE anterior sigue permitiendo fusionar B equivalente. Esto documenta
el formato actual; no propone admitir el campo ni ignorar HOLD válidos.

## Validez y alcance

Se reutilizan el gh falso y el remoto bare temporal de la suite. Los commits
y los merges de main son reales; no se sustituye `head_equivalent` ni
`reviews_ok`. El orden de las revisiones se fija con llamadas consecutivas a
`review-register`, sin sleeps ni dependencia de timestamps distintos.

Los cuatro tests rojos fallan contra el código anterior, que se conserva
intacto. Los seis controles verdes también fallan al mutar una aserción
decisiva por test en una copia temporal: PR fusionada incorrecta o motivo de
aparcado incorrecto. Esto comprueba que las aserciones se alcanzan; no es una
medición de cobertura de mutación de producción.

No se corrige el incidente, no se cambia el contrato del registro y no se
concede autoridad de merge. La publicación debe declarar los cuatro rojos;
si un gate la impide, se deja la rama local para la orquestadora, sin bypass.

## Impedimentos de cierre

- SAM regenerado y comprobado: **FRESH**, 2836 nodos. El mapa de capacidades
  se regeneró sin cambios versionados en `.scm` (derivados locales, SE-501).
- Entropía no comprobable: `derived.sh` no puede crear `savia-derived.lock`
  en los metadatos del worktree: `Read-only file system`. No se cambia el
  cerrojo, la ruta ni los permisos para sortearlo.
- `git add` falla al crear `index.lock`: `Read-only file system`. No hay
  commit, push ni PR; los tres ficheros quedan en el worktree para recogerlos.
- `confidentiality-sign.sh sign` devuelve 2: firma retirada por SE-501;
  no se fabrica una firma ni se versionan derivados retirados.

Verificación completa: las cuatro suites `test-merge-sprint*.bats` ejecutan
**227 tests: 223 pasan y solo fallan los cuatro casos nuevos indicados**.
`git diff --check` pasa. El auditor de tests da **90/100**, certificado.
`confidentiality-scan.sh --pr` devuelve clean sin líneas que escanear porque
no hay commits; no certifica los cambios locales sin versionar.
El cierre `validate-ci-local.sh --clean-state` devuelve 1: 15 comprobaciones
pasan y tres fallan (dos de derivados y cobertura L4 no evaluable).

## Implementación (encargo ms-hold-impl)

Cambio en `scripts/merge-sprint.sh`, sin tocar los tests de Codex ni el formato de `reviews.jsonl`.
Nueva función `hold_blocks <pr> <sha_usado> <cabeza_actual>`, que se consulta en tres puntos:
el plan (tras elegir la revisión usada), la entrada de run (antes de re-sincronizar) y `try_merge`
(justo antes de `merge_at`, sobre la cabeza que se va a fusionar).

Regla: retiene un HOLD de la PR sobre la cabeza actual o sobre el sha usado, y cualquier otro HOLD de la
PR que no tenga detrás, en el orden del registro, un APPROVE íntegro del mismo rol sobre el sha usado.
Si el registro da error, también retiene.

Discrepancias y decisiones:
- La regla no exige que el sha del HOLD sea equivalente a la cabeza. `head_equivalent` devuelve 1 tanto si
  hay error como si no hay equivalencia, y usarla aquí abriría el gate ante un error. Consecuencia: un HOLD
  tardío sobre una cabeza vieja y no equivalente también retiene, hasta que se registre un APPROVE nuevo.
- Con los tests de Codex, quitar la comprobación de entrada de run no hace caer ningún test, porque
  `try_merge` la cubre. El test `HOLD-impl run entrada` lo separa: la PR retenida no se re-sincroniza.
