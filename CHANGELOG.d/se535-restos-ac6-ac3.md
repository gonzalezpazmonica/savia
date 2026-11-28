---
version_bump: patch
section: Fixed
---

### Fixed

- SE-535 RESTO-535-a (AC-6): nueva suite `tests/bats/se535-ac6-skills-externas.bats`. Detecta `ln -s` hacia un directorio de skills y `git clone` de un repositorio de skills sin commit de 40 hex (en la misma orden o en la siguiente), con casos sembrados que lo disparan, casos limpios que no y una pasada sobre todos los guiones versionados. Hasta ahora la ausencia de skills externas descansaba solo en que el instalador ya no existía.
- SE-535 RESTO-535-b (AC-3): `scripts/test-multi-tenant.sh` vuelve a verde. Las dos comprobaciones de comunidad de las README buscaban textos que la reescritura de `b07306e88` quitó; ahora aceptan también el enlace de la sección Contribuir/Contributing a CONTRIBUTING.md, que es por donde hoy se llega a la comunidad.
