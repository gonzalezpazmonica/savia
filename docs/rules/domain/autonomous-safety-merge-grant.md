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

## Referencias

- Regla madre: `docs/rules/domain/autonomous-safety.md` § Reglas de PRs
- Spec: `docs/specs/SE-343-operator-grant-switch.spec.md`
- Implementación: `scripts/operator-grant.sh`, `scripts/push-pr.sh`,
  `scripts/savia-double-optin-check.sh`
