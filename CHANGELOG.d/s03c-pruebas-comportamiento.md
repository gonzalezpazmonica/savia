---
version_bump: patch
section: Fixed
---

### Fixed

- sagi-e2e.sh: un goal con comillas dobles, barras, saltos de línea o tabuladores ya no rompe el JSON de salida.
- pre-llm-tabular-detect.sh: prosa y CSV en el mismo prompt ya se perfilan (la prosa se leía como cabecera y caía a datos crudos). Las filas CSV se eligen por número de comas modal entre las filas con dígitos, de modo que la cabecera se conserva y la prosa con comas ("Hola, analiza esto") ni se perfila ni se pierde.
- memory-save.sh: --supersedes con claves de topic con barra (tipo/slug) ya marca la entrada antigua (sed fallaba con el delimitador); `|` en la clave ya no actúa como alternancia y `\` o `&` en la clave nueva se escapan en el reemplazo.
- env-scrub.sh: PATH, PYTHONPATH, MYPATH y similares ya no cuentan como credenciales; PAT pegado (GHPAT, AZDOPAT), GH_PAT y TOKEN= sin prefijo se detectan; --list-dropped no lista la allowlist.
- freetoken-probe.sh: se leen todas las banderas (la última se ignoraba; ahora una bandera desconocida da exit 2 en cualquier posición, antes se ignoraba tras la primera). La compuerta de compute capability usa aritmética entera: sin `bc` instalado toda GPU salía inviable; acepta `8.6` y `8,6`.
- Tests: 28 aserciones `! cmd` a mitad de test (que en bats no pueden fallar) pasan a `if cmd; then false; fi`.
- Pruebas de comportamiento nuevas para 17 ficheros de test (SCL, tabular, savia-env, memory-store, env-scrub, repeat-tool-guard, freetoken-probe, turn-budget-inject).

