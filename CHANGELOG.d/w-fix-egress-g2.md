---
version_bump: patch
section: Security
---

### Security

- credential-egress (SE-353, hallazgo G2): `resolve` sin `--dest` ya no imprime el secreto (REFUSE fail-closed); la allowlist compara destinos exactos; `store` lee el valor por stdin y rechaza el valor por argv; `run` deriva el destino de `--dest` o del host único de las URLs y rechaza destinos ambiguos o discrepantes. 11 tests BATS nuevos.

