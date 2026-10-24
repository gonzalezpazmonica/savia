---
version_bump: patch
section: Fixed
---

### Fixed

- Calidad S03h: pruebas de comportamiento validadas por mutación para 9 ficheros de test (contract-pin, model-gateway, savia-catalog, savia-workspace, savia-setup, incident-rca, judge-calibration, sldc-context-loop, sdd-research-lane); 222 de 254 mutantes muertos (antes 122), los 32 supervivientes analizados.
- Fix: `savia-setup.sh` guardaba como proveedor y frontend el texto entero del menú (el menú salía por stdout dentro de `$(...)`), el modo de vault «remoto» nunca coincidía con `remote` y el cierre del asistente no se ejecutaba; `activated_at` y `updated_at` eran una fecha fija (también en `savia-workspace.sh`).
- Fix: `judge-calibration.sh` no registraba el juez en `--dispose` (los informes por juez salían siempre vacíos), aceptaba el prefijo `descartado` como disposición, ejecutaba como código Python lo que contuvieran id, juez o descripción y fallaba con argumentos ausentes.
- Fix: `sldc-context-loop.sh` daba por entregada una nota si la cúpula no respondía (se perdía), `--flush-pending --dry-run` vaciaba la cola y se ignoraba según el orden de las opciones, y la vista previa escapaba los acentos.
- Fix: `sdd-research-lane.sh` se quedaba en un bucle infinito si una opción con valor (`--grant`, `--claim`, `--a`…) iba al final sin él.
- Fix: `model-gateway.py` no vaciaba el búfer del aviso de arranque al redirigir la salida.
