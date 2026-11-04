---
version_bump: patch
section: Added
---

### Added

- SE-498 PROPOSED (solo spec): STOP global y revocación entre ejecutores — inventario de los cuatro STOP, pause/revoke/quarantine/reconcile/resume, época de revocación consultada por SE-496 y SE-493, ADV-09/10/18 como AC. Tras revisión: aprobación de `resume` de un solo uso y ligada a la parada (`stop_seq`), `REJECTED` terminal en el ledger (`ABANDONED`), marca de instalación fuera del directorio de control para que borrar el estado no deshaga una revocación, y lista de permitidas del gate con rutas absolutas. Segunda revisión: estado por ámbito con modo efectivo (el más restrictivo de las paradas que cubren), `resume` sin `reconcile` previo sale 5 (`RECONCILE_REQUIRED`), los adaptadores consultan `check` (modo y época) antes de cada efecto, marca de instalación resuelta desde el script y no desde el cwd, aridad fija de opciones y `--reason` libre entre comillas simples en el gate.
