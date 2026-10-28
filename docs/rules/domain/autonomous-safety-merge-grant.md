---
context_tier: L3
token_budget: 1000
---

# Merge bajo permiso expreso — SE-343 (apéndice de autonomous-safety.md)

> Apéndice extraído de `docs/rules/domain/autonomous-safety.md` para mantener el
> host bajo el cap de 150 líneas (Rule 11). Misma doctrina, mismo peso de regla.

De base, `push-pr.sh --merge` NO mergea: exige un **grant `merge` vigente**
registrado en el ledger local (`~/.savia/grants/`) vía
`operator-grant.sh grant --scope merge --resource pr:<n> --context "<petición>"`.
Savia solo emite el grant cuando la operadora lo pide **expresamente**; nunca se
auto-concede (`source != self`). El grant vale para **un** PR o tarea y se
**consume** tras el merge (one-shot, TTL 6h por defecto). Si la operadora es la única colaboradora,
puede revisar y mergear sus PRs sin un reviewer distinto. Para tier 1/2, el
grant permite merge tras CI y gates; tier 3/4 exige revisión humana explícita
del PR concreto (SE-362).

El flujo, en tres pasos (el grant firma la cabeza **definitiva** del PR):

1. `push-pr.sh` **sin** `--merge` firma la confidencialidad, empuja la rama y
   crea o actualiza el PR. Esa cabeza publicada es la que se fusionará.
2. La operadora pide merge → Savia prepara la petición de `pr:<n>` (lleva esa
   cabeza) → la operadora la firma → Savia incorpora la firma.
3. `push-pr.sh --merge` **no firma, no empuja ni toca el PR**: comprueba que el
   árbol está limpio, que la cabeza local es la publicada en `origin`, que la
   firma de confidencialidad la cubre (`confidentiality-sign.sh verify`), que
   hay un PR abierto para la rama y que el grant de `pr:<n>` firma esa misma
   cabeza; entonces mergea y el grant se consume (`consume`).

Si falla cualquiera de esas comprobaciones, aborta con 1 sin empujar nada y
explica cómo preparar la rama. Sin grant (nadie autorizó), el PR permanece en
Draft. Cualquier commit posterior al grant (también una re-firma) mueve la
cabeza: hay que repetir los pasos 1 y 2. `--merge` no firma ni empuja porque
el firmador escribe hora y cabeza en cada firma: firmar en la ejecución de
merge creaba siempre un commit nuevo, y la cabeza dejaba de ser la firmada.

El grant firma un contenido, no un número de PR: `check` compara `head_sha` con
la cabeza actual del PR y falla cerrado si difiere o no se puede leer.
`check --print-head` devuelve el `head_sha` firmado del grant verificado y
`push-pr.sh` pasa ese valor (no la cabeza local) a
`gh pr merge --match-head-commit <sha>`: GitHub rechaza el merge
si la cabeza del PR no es la que firmó la operadora, aunque la comprobación
local se hubiera falseado. Si la cabeza firmada no es la local, ni se intenta.
`gh` se toma solo de un PATH fijo de sistema; el gh simulado de las pruebas
(`SAVIA_GH_BIN`) solo se acepta con `SAVIA_GRANT_TEST_MODE=1`, y en ese modo
`push-pr.sh --merge` se niega a mergear.

Si `consume` falla tras el merge, se revoca el grant y se avisa. El merge es
inmediato y el grant se vuelve a comprobar justo antes: nunca se programa un
auto-merge (`gh pr merge --auto`), que GitHub ejecutaría al ponerse verde el CI
aunque el grant se hubiera revocado o caducado. Si el PR no se puede mergear
todavía, sale con 1 sin gastar el grant y se vuelve a ejecutar
`push-pr.sh --merge` con el CI en verde (no mueve la cabeza, así que el mismo
grant sigue valiendo). `--merge` necesita `gh` autenticado. `gh` actúa siempre
sobre el repo de `origin` (`-R`, sin `GH_REPO`/`GH_HOST`), el mismo para el que
va firmado.

## Firma de la operadora (LAW-HUMAN-002, firma asimétrica)

Savia no puede emitir el grant sola: `operator-grant.sh grant` deja una
petición canónica (id, `grantor`, `scope`, `repo`, `resource`, `head_sha`,
vigencia) en `~/.savia/grants/merge.request` y sale con 4. La operadora la
firma con su clave ed25519 **privada** (móvil o Savia Space, nunca el equipo de
los agentes) y `grant --signature` incorpora la firma. `check` verifica cada
campo y la firma contra el fichero de firmantes **de `origin/main`** (nunca la
copia de trabajo): sin esa raíz, o con un grant alterado, de otra petición,
repo, PR o scope, caducado (máx. 24 h), consumido o revocado, no vale.
`push-pr.sh --merge` rechaza PRs que tocan ese fichero y tier ≥ 3.

Detalle completo (alta de la clave, qué prueba la firma, límites del guard y
del verificador, libro `merge.spent`):
`docs/rules/domain/autonomous-safety-merge-grant-reference.md`.


## Referencias

- Detalle de la firma: `docs/rules/domain/autonomous-safety-merge-grant-reference.md`
- Regla madre: `docs/rules/domain/autonomous-safety.md` § Reglas de PRs
- Spec: `docs/specs/SE-343-operator-grant-switch.spec.md`
- Implementación: `scripts/operator-grant.sh`, `scripts/push-pr.sh`,
  `scripts/savia-double-optin-check.sh`
