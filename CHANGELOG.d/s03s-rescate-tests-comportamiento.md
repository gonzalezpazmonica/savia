---
version_bump: patch
section: Fixed
---

### Fixed

- S03s (SE-376): pruebas de comportamiento discriminante para 7 ficheros de test de gates (rescate del worker s03s); mutantes muertos de 18/131 a 126/131 en la batería manual (los 5 restantes son equivalentes).
- attack-surface-map: el gate de autorización ya no acepta 'NOT AUTHORIZED' y --target se valida como nombre DNS; los tests dejan de lanzar el escáner real y de escribir en output/security.
- learning-guard: la auditoría de escritura revisa todos los destinos del bucle y --expect-constitution-sha256 verifica que la CONSTITUCION no cambie.
- planning-completion: el predicado de cierre rechaza un fichero de evidencia con salto de línea.
- glm-compute-digest: solo sustituye manifest_digest.value (antes corrompía otros campos value y el digest no verificaba).
- evals-paired-delta: sin ids comunes sale 2 (sin veredicto) en vez de 0; evals-runner y check-skill-evals no revientan con entradas inválidas.

