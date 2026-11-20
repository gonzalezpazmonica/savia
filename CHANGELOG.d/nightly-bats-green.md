---
version_bump: patch
section: Fixed
---

### Fixed

- La suite nocturna completa de BATS vuelve a poder pasar: arregla 20 de las 31 suites que fallaban (y deja 5 más a cargo del workflow) en main desde al menos el 2026-11-12 (tests desactualizados respecto a contratos cambiados, una bomba de reloj de fecha, dos barridos de 74 s repetidos por test, un hook con supresión silenciosa y un preregistro F4 incompleto) y el workflow nocturno instala ahora las dependencias de savia-vaults, genera los derivados (SE-501) y el locale es_ES.UTF-8 que las suites necesitan.
- Los dos tests intermitentes del nocturno (SPEC-181 JSON y commit-guard sin jq) parsean solo stdout y, si fallan, dejan stdout y stderr en el TAP.
- El ejecutor de la suite nocturna pasa a `scripts/nightly-bats-run.sh` (con tests): las rutas llegan entrecomilladas como argumento, una suite que no registra su código de salida cuenta como fallo `missing` en vez de desaparecer del total, y el checkout ya no deja el token en `.git/config`.
- El marcador `# nightly: serial` solo vale en las 3 primeras líneas de la suite, el resumen de la nocturna muestra el timeout configurado y el test de `missing` ya no depende del orden de arranque de xargs.
- Las suites ya no escriben en el árbol real del repo mientras otras lo recorren en paralelo: `test-ci-actions-pinned`, `test-ci-token-permissions`, `test-requirements-hashed` y `test-se-172-markitdown` crean sus fixtures en su directorio temporal; `test-compile-agent-index` (con `AGENT_INDEX_FILE` en `compile-agent-index.sh`) y el AC4 de `test-critical-facts-cap` trabajan sobre copias de `.claude/AGENTS-INDEX.md` y `docs/critical-facts.md`. Un test de `test-nightly-bats-run` impide volver a crear temporales bajo el repo. `test-hook-bench-confirm` y `test-operator-grant` (miden reloj real) pasan al carril serie, y el test 23 de `test-eval-lint` imprime la salida si falla.
- `test-knowledge-graph` dejaba de ser intermitente: `echo "$output" | grep -q` con `pipefail` falla por SIGPIPE cuando grep cierra antes de que echo termine de escribir una salida grande; ahora usa here-string.
