---
version_bump: patch
section: Security
---

### Security

- credential-egress (SE-353, hallazgo G2): `resolve` sin `--dest` ya no imprime el secreto (REFUSE fail-closed); la allowlist compara destinos exactos (sin distinguir mayúsculas); `store` lee el valor por stdin y rechaza el valor por argv; `run` deriva el destino de `--dest` o del host único de las URLs que aparezcan en cualquier posición de los args (también `--url=` y scripts de `bash -c`) y rechaza destinos ambiguos, discrepantes o con autoridad ambigua (`\`, `%`). La comprobación es salvaguarda de enrutado, no barrera frente a un llamante hostil: límites documentados en `secret-redaction-policy.md`. 18 tests BATS nuevos.
