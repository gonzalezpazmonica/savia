---
version_bump: patch
section: Fixed
---

### Fixed

- hook-bench-all confirma con 15 muestras los hooks críticos que superan el SLA con 5 (el ruido de un runner compartido ya no suma violaciones) y el ratchet de latencia de ci-extended-checks nombra los hooks infractores en lugar de solo contarlos. El baseline no cambia.

