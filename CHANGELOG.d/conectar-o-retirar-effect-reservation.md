---
version_bump: patch
section: Removed
---

### Removed

- SE-493 S4: eliminado `scripts/effect-reservation.sh` (contrato de reservas deprecado, sin ningún consumidor en hooks, scripts, workflows ni lanzadores) y su test redundante `f5-exactly-once.bats`; `coherence-gates.sh` deja de listarlo como cierre pendiente. El contrato vivo de `pr.merge` sigue siendo `scripts/f5-state.sh`.

