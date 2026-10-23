---
version_bump: patch
section: Fixed
---

### Fixed

- Pruebas de comportamiento para 10 ficheros de test por debajo de 80 sobre scripts muy usados (handback, origen de memoria, soberanía, fingerprint de telemetría, patrones de fallo, propuestas de aprendizaje, fronemas, scope-creep, bus factor scan/distribute); 268 mutantes, 257 muertos.
- Fix: `fronema.py calibrate` caía con KeyError al sugerir graduar (3.ª sesión >= 90 %).
- Fix: `scope-creep-check.sh` trataba como related los ficheros de la raíz y los directorios con prefijo de texto igual; `bus-factor-scan.py` excluía `vendor_client.py`/`vendored/` por el patrón `vendor/`; `telemetry-alert.sh --dry-run` escribía el log.

