---
version_bump: patch
section: Removed
---

### Removed

- SE-535 S2: se retira la integración externa Understand-Anything: `scripts/ua-install.sh`, `scripts/ua-bridge.sh`, las siete órdenes `/ua-*`, la skill `understand-anything` y sus dos suites. El instalador clonaba un repositorio externo sin versión fijada y enlazaba sus skills sin leerlas; no constaba ningún uso. Se limpian catálogos, índices y la excepción de instalaciones sin fijar. `SPEC-SE-088-UA-ADOPT` queda marcada como retirada. Recuentos: órdenes 568 → 561 (557 en los README), skills 140 → 139. Se recupera del historial de git.
