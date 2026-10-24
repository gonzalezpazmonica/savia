---
version_bump: patch
section: Fixed
---

### Fixed

- Calidad S03j: pruebas de comportamiento validadas por mutación para 10 ficheros de test (mobile-security-scan, pre-push-security-gate, memory-feedback-extractor, learning-divergence, learning-autonomy, audit-receipts, agent-request-validate, detect-token-exhaustion, auto-loop-gate, coherence-court); 230 de 252 mutantes muertos (antes 129 de 249), los 22 supervivientes analizados.
- Seguridad: `agent-request-validate.sh` interpolaba el `agent-id` dentro del código Python de la comprobación de tarjetas; un id con comillas (`zz' or 'a'=='a`) devolvía ACCEPT con cualquier tarjeta activa. Los valores viajan ahora por entorno (también en el registro de identidad).
- Fix: `detect-token-exhaustion.sh --log` sin valor giraba para siempre; ahora sale con error.
- Fix: `memory-feedback-extractor.py` no marcaba fallo con «fail» en minúscula (la expresión era `failed?`) y lanzaba `AttributeError` con un payload JSON que no es objeto.
- Fix: el uso de `learning-autonomy.sh` y `learning-divergence.sh` se cortaba antes de las opciones y los códigos de salida.
