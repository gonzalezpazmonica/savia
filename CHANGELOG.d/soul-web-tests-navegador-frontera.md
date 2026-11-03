---
version_bump: patch
section: Fixed
---

### Fixed

- SE-490 web: los tests que lanzan un navegador viven en test/navegador/ y solo corren en soul-continuity-web, en serie y con el Chromium fijado por SOUL_NAVEGADOR (obligatorio en CI); el paso «sin navegador» del job general ya no arranca el Chrome del runner (fallo intermitente de 15 s en la PR #1447). Un test vigila la frontera, los scripts y los workflows.

