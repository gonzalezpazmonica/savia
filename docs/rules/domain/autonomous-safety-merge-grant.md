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

El flujo correcto: la operadora pide merge → Savia prepara la petición con
contexto → la operadora la firma → Savia incorpora la firma →
`push-pr.sh --merge` verifica el grant de `pr:<su número>` y mergea → el grant
se consume (`consume`). Sin grant
(nadie autorizó), `push-pr.sh --merge` aborta y el PR permanece en Draft.

## Firma de la operadora (LAW-HUMAN-002, firma asimétrica)

Pedir el grant no basta y Savia no puede emitirlo sola:

1. `operator-grant.sh grant --scope merge --resource pr:<n> --context "..."`
   solo deja una petición canónica en `~/.savia/grants/merge.request` y la
   imprime (exit 4). Lleva id aleatorio, `grantor` (principal), `scope`,
   `resource` y vigencia (`issued_epoch`, `expires_epoch`).
2. La operadora la firma con su clave ed25519 **privada**, que vive en su móvil
   o en Savia Space y nunca en el equipo de los agentes:
   `ssh-keygen -Y sign -f <clave> -n savia-operator-grant <petición>`.
3. `operator-grant.sh grant --scope merge --signature <petición>.sig` (o
   `--signature -` pegando la firma) verifica e incorpora la firma.

`check --scope merge --resource pr:<n>` verifica cada vez, en el punto de uso,
cada campo firmado y la firma con `ssh-keygen -Y verify` contra
`config/operator-grant-signers` (formato `allowed_signers`, identidad =
`grantor`, namespace `savia-operator-grant`). Un `merge.json` escrito a mano,
alterado, firmado por otra clave, con otro namespace, de otra petición, de otro
PR o scope, caducado, consumido o revocado no vale. Sin `--resource`, sin
ninguna clave en ese fichero o sin `ssh-keygen`, ningún grant de merge es válido.

`consume` y `revoke` apuntan el id en `~/.savia/grants/merge.spent`; `check`
rechaza esos ids, así que restaurar una copia guardada del grant no lo revive.

### Qué prueba la firma y qué no

Una firma válida prueba que se usó la clave privada registrada, **no** que
hubiera una persona delante. La garantía de presencia humana viene de la
ceremonia: la clave privada vive solo en el móvil de la operadora (o en Savia
Space), con frase de paso, y nunca en el equipo de los agentes. Si la clave
saliera de ahí, la firma dejaría de probar nada sobre ella.

### Alta de la clave (procedimiento manual de la operadora)

1. En el móvil (p. ej. Termux) o en Savia Space:
   `ssh-keygen -t ed25519 -f ~/.ssh/savia-grant -C savia-grant`, con frase de paso.
2. Copiar SOLO la pública (`savia-grant.pub`) y añadir una línea a
   `config/operator-grant-signers`:
   `<active_slug> namespaces="savia-operator-grant" ssh-ed25519 AAAA...`.
3. Hacerlo por PR propia y mergearla ella: el hook `operator-grant.sh guard`
   veta a los agentes editar ese fichero.
4. Rotación o pérdida del móvil: quitar la línea antigua y añadir la nueva por
   el mismo camino. Quitarla invalida al instante los grants ya firmados.

Límite: el guard ve el texto de la orden, no lo que ejecuta un script escrito
antes ni un cambio de rama; la defensa de fondo es que el fichero es versionado
y su cambio pasa por una PR que solo mergea la operadora. Lo mismo vale para el
verificador (`scripts/operator-grant.sh`, `scripts/push-pr.sh`): en su rama, un
agente puede cambiarlos; la frontera real es que el merge a `main` lo revisa y
lo hace la operadora. El libro `merge.spent` es local: quien pueda borrarlo y
conserve una copia podría reusar el grant, pero solo para el mismo PR (el
recurso va firmado) y dentro de su vigencia.

## Referencias

- Regla madre: `docs/rules/domain/autonomous-safety.md` § Reglas de PRs
- Spec: `docs/specs/SE-343-operator-grant-switch.spec.md`
- Implementación: `scripts/operator-grant.sh`, `scripts/push-pr.sh`,
  `scripts/savia-double-optin-check.sh`
