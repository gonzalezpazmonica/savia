---
context_tier: L3
token_budget: 1000
---

# Merge bajo permiso expreso — SE-343 (apéndice de autonomous-safety.md)

> Apéndice extraído de `docs/rules/domain/autonomous-safety.md` para mantener el
> host bajo el cap de 150 líneas (Rule 11). Misma doctrina, mismo peso de regla.

De base, `push-pr.sh --merge` NO mergea: exige un **grant `merge` vigente**
registrado en el ledger local (`~/.savia/grants/`) vía
`operator-grant.sh grant --scope merge --context "<petición de la operadora>"`.
Savia solo emite el grant cuando la operadora lo pide **expresamente**; nunca se
auto-concede (`source != self`). El grant se **consume** tras el primer merge
exitoso (one-shot, TTL 6h por defecto). Si la operadora es la única colaboradora,
puede revisar y mergear sus PRs sin un reviewer distinto. Para tier 1/2, el
grant permite merge tras CI y gates; tier 3/4 exige revisión humana explícita
del PR concreto (SE-362).

El flujo correcto: la operadora pide merge → Savia emite el grant con contexto →
`push-pr.sh --merge` verifica el grant y mergea → el grant se revoca. Sin grant
(nadie autorizó), `push-pr.sh --merge` aborta y el PR permanece en Draft.

## Prueba de persona y firma (LAW-HUMAN-002, patrón Yema F4)

Pedir el grant no basta: `grant --scope merge` mide quién lo concede.

- **Terminal de la operadora**: escribe `MERGE` en `/dev/tty` → `source: tty`.
- **Diálogo del arnés**: `operator-grant.sh guard` (PreToolUse) responde
  «ask», que el modelo no puede pulsar, y deja un ticket de un solo uso (5 min)
  ligado al scope y al contexto exactos → `source: harness-ask`. En
  `bypassPermissions` y `dontAsk` deniega.
- Sin terminal ni ticket: exit 4 y no se escribe nada.

El grant se firma con HMAC-SHA256 y una clave local fuera del repo (0600, en
`~/.savia/`), que el guard veta a las herramientas. `check` solo da por vigente
un grant de merge con firma válida y `source` medido: un `merge.json` escrito a
mano, alterado o firmado con otra clave no vale.

Límite: el guard ve el texto de la orden, no lo que ejecuta un script escrito
antes, y la clave la puede leer cualquier proceso del mismo usuario. El ticket
prueba que se preguntó, no quién contestó.

## Referencias

- Regla madre: `docs/rules/domain/autonomous-safety.md` § Reglas de PRs
- Spec: `docs/specs/SE-343-operator-grant-switch.spec.md`
- Implementación: `scripts/operator-grant.sh`, `scripts/push-pr.sh`,
  `scripts/savia-double-optin-check.sh`
