---
version_bump: patch
section: Fixed
---

### Fixed

- sagi-e2e.sh: un goal con comillas dobles o barras ya no rompe el JSON de salida.
- pre-llm-tabular-detect.sh: prosa y CSV en el mismo prompt ya se perfilan (la prosa se leía como cabecera y caía a datos crudos).
- memory-save.sh: --supersedes con claves de topic con barra (tipo/slug) ya marca la entrada antigua (sed fallaba con el delimitador).
- env-scrub.sh: PATH, PYTHONPATH y similares ya no cuentan como credenciales; TOKEN= sin prefijo ya se detecta; --list-dropped no lista la allowlist.
- freetoken-probe.sh: se leen todas las banderas (la última se ignoraba) y la compuerta de compute capability no depende del locale.
- Pruebas de comportamiento nuevas para 17 ficheros de test (SCL, tabular, savia-env, memory-store, env-scrub, repeat-tool-guard, freetoken-probe, turn-budget-inject).

