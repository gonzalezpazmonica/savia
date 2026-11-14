---
version_bump: patch
section: Added
---

### Added

- SE-533 (PROPOSED): límites compartidos de delegación entre agentes: presupuesto por encargo (profundidad, concurrencia, lanzamientos, repeticiones), permiso de quién puede pedir a quién cerrado por defecto, detección de repeticiones y de compañeros que fallan tres veces seguidas, y arreglo del analizador que da PASS a ciclos y atajos. Seis slices con AC, casos negativos, tier y reversión. Solo spec y test de coherencia; ningún guard, agente ni script cambia.

