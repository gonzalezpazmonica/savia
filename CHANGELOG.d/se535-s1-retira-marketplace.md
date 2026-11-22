---
version_bump: patch
section: Removed
---

### Removed

- SE-535 S1: se retiran las órdenes `/marketplace-install`, `/marketplace-search` y `/marketplace-publish`. Eran ficheros de instrucciones sin implementación: citaban un registro que no existe y ningún guion. Se limpian sus referencias en el mapa de contexto, la configuración, las órdenes de tenant y el índice, y SE-443 S2 deja de apoyarse en una de ellas. `scripts/test-multi-tenant.sh` pasa a comprobar que no reaparecen. Recuento de órdenes: 571 → 568.
