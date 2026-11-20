---
version_bump: minor
section: Fixed
---

### Fixed

- SE-510 S2: gh pr create desde un worktree mira el .pr-summary.md de ese árbol (resolvedor scripts/lib/pr_summary_root.py; el gate lo coloca la operadora) y anuncia el encabezado exigido con plantilla docs/templates/pr-summary.md y aviso en pr-plan.
- SE-510 S2: paridad de veredictos bash/TS sobre el corpus (guard-corpus --ts, exit 4 si difieren) y cierre del hueco TS que dejaba pasar un add o un commit con destino no resoluble.
- SE-510 S2: registro local de bloqueos con tasa de falsos positivos (scripts/guard-blocks.sh record|mark|report|wrap, HMAC con clave local, sin la orden en claro); los guards TS ya registran.

- SE-510 S2 (revisión): el resolvedor bloquea con varios cd, un cd en subshell ya cerrado, pushd/popd y env -C; el registro redacta el motivo, nace 0600 y wrap entrega al hook los mismos bytes sin cambiar su código; los guards TS solo registran errores con marca BLOCKED/BLOQUEADO.
- SE-510 S2 (CI): scripts/hooks-coverage-matrix.sh lee también .opencode/plugins/lib/before-guards.ts cuando el plugin la importa; sin ello 13 guards TS salían como NONE y el --check fallaba.
- SE-510 S2 (revisión independiente 2026-11-17): el resolvedor del cd solo sigue un cd literal en primera posición y bloquea cualquier otro cd (builtin, `||`, pipe, saltos de línea, comillas, bash -c, llaves, if) antes del último gh pr create; el guard TS trata `git stage` como `add` si falta el resolvedor; la redacción tapa valores entrecomillados y opciones `--token`/`-p`; wrap sale 2 con una opción sin valor (antes quedaba en bucle) y pasa `--reason=`; el log no sigue enlaces simbólicos; la clave tolera la carrera de creación.
- SE-510 S2 (revisión Codex 2026-11-20): el resolvedor del cd borra continuaciones de línea como bash, detecta `cd` escapado o entrecomillado (c\d, c''d), bloquea si un `&` deja el cd en segundo plano o si el directorio no es un repo git; el resolvedor común y el guard TS ven git add/commit partidos con `\`+salto; el gate conserva el cwd de la entrada de respaldo; los guards TS solo registran errores que empiezan por la marca; la clave HMAC se lee sin seguir enlaces y solo si es de la propia usuaria.
- SE-510 S2 (revisión 2026-11-21, a15100d): el resolvedor del árbol de gh bloquea `env -C<ruta>`/`env -iC`, `pushd`/`popd` en cualquier posición (`builtin pushd`) y un gh disfrazado (`\gh`, `"gh"`), y ya no toma un `&` entre comillas o escapado por segundo plano; validateBashGlobal (TS) sin resolvedor bloquea también `"$x" … commit`; el registro de bloqueos redacta todo lo que reconoce el guard de credenciales (Vault, Google, Azure/SAS, JWT, PEM, connection_string) y recibe el motivo por el entorno (`SAVIA_GUARD_BLOCK_REASON`), no por argv.
