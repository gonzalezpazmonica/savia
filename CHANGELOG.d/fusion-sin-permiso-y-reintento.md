---
version_bump: patch
section: Security
---

### Security

- `scripts/review-community.sh merge` queda retirado: fusionaba una PR sin permiso firmado de la persona, sin comprobar la revisión y sin atar la fusión al commit revisado. Ahora rehúsa con código 3 y remite a `merge-sprint.sh`.
- `scripts/push-pr.sh` ya no fuerza la subida ante cualquier fallo: el reintento con `--force-with-lease` solo se dispara cuando el remoto rechaza por historia divergente. Un fallo de red, de permisos o de rama protegida se informa y aborta.
- Tests con caso negativo y contraprueba para ambas rutas (A09 y A02 del inventario de rutas de efecto del 2026-11-02).
