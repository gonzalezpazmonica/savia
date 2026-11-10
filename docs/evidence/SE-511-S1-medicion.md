# SE-511 S1 — Medición del contexto fijo por turno

Medido con `bash scripts/context-fixed-measure.sh` (método: caracteres / 4, entero hacia abajo, sobre el total). Commit de partida: a81c868dd.

## Cifras (línea base congelada)

| Modo | Bytes | Caracteres | Tokens | Baseline |
|---|---|---|---|---|
| `--versioned` (CLAUDE.md + 6 imports) | 27.826 | 27.489 | **6.872** | `.ci-baseline/context-fixed-tokens.count` |
| `--hooks` (fixture fija, HOME vacío, worktree desechable detached, 2 ejecuciones idénticas) | 585 | 571 | **142** | `.ci-baseline/context-fixed-hooks-tokens.count` |
| `--local` (perfil activo y memoria externa) | solo local | | informe, aviso > 6.000, sin gate | — |
| `--versioned --entry opencode` (suma `.opencode/CLAUDE.md`) | 31.669 | 31.142 | 7.785 | sin gate |

Diferencia con la spec (27.633 B en be2fca5aa): `CLAUDE.md` pasó de 8.394 a 8.587 B desde entonces (+193 B); los otros 6 ficheros no cambian. La spec medía be2fca5aa; el test AC-1 comprueba ese commit exacto cuando está disponible.

Sin calcular aún (fuera de S1): recuento del endpoint de conteo del proveedor (D2, «el mayor de los dos»). Requiere credencial y red; el script usa solo el método versionado.

## Clasificación de cada fuente

Núcleo = va en el bloque compacto de S2. Gate = puede salir del texto fijo cuando exista hook o script con test (D5). Bajo demanda = se lee cuando el turno lo pide. Retirable = ruido sin función en el arranque.

| Fuente | Tokens | Clase | Motivo |
|---|---|---|---|
| `CLAUDE.md` — entrada/cierre, reglas 1-8, estructura | ≈ 1.100 | núcleo (recortable) | Reglas 1-3 y 7 son de gestión de proyectos: candidatas a bajo demanda. |
| `CLAUDE.md` — tabla «Lazy Reference» | ≈ 1.130 | bajo demanda | 4,5 KB que sustituye un puntero a `docs/RESOLVER.md`. |
| `docs/critical-facts.md` | 258 | núcleo | Tope SPEC-185; gates inmutables. |
| `.claude/profiles/savia.md` | 1.645 | núcleo + retirable | Identidad canónica, género y tono son núcleo; los ejemplos de alertas de sprint, el registro por perfil y «Frases que no dice» se pueden leer bajo demanda (condición S0: conservar 2-3 frases modelo). |
| `docs/rules/domain/radical-honesty.md` | 1.324 | núcleo + bajo demanda | Prohibiciones y obligaciones son núcleo; ejemplos antes/después y tabla de tono, bajo demanda. |
| `docs/rules/domain/autonomous-safety.md` | 792 | gate parcial | Git y PRs ya tienen hook (`block-commit-to-main.sh`, `block-force-push.sh`, `repeat-tool-guard.sh`, `merge-sprint.sh`); investigación y fail-safe no tienen código: se quedan. |
| `docs/rules/domain/caveman-default.md` | 519 | núcleo | Sin enforcement; la brevedad solo existe como texto. |
| `docs/rules/domain/knowledge-discovery-priority.md` | 215 | núcleo | SE-335: telemetría en modo sombra, no gate. |
| Salida de hooks (`--hooks`): `session-init.sh` | ≈ 125 | núcleo | Mensaje de arranque. |
| Salida de hooks: `check-daemon-auth.sh` | ≈ 20 | retirable | Con HOME vacío siempre avisa «auth expired»; en uso real depende del estado local. |
| Hooks de UserPromptSubmit (8) | 0 con la fixture | bajo demanda | Inyectan solo con estado previo (memoria, sesión caliente); medir con `--local` si hace falta. |
| `windows-links.sh repair` | 0 | — | Se mide como los demás (en la copia desechable sus escrituras no tocan el repo). Si `repair` falla, su aviso cuenta. |
| Perfil activo e índice de memoria externa | solo `--local` | núcleo | Gitignored; cifras por operador, sin gate. |

## Límites del método

- Los `@imports` se resuelven relativos a la raíz en todos los niveles (convención del repo). Un import pensado como relativo al fichero importador se mide como inexistente (error) si no existe en la raíz; si existe en las dos rutas, se mide el de la raíz (test «import anidado se resuelve desde la raíz»). Rutas absolutas o con `..` que salgan de la raíz son error.
- `--versioned` no lee ficheros gitignored: la cifra no depende de qué haya en la máquina.
- `--hooks` corre los hooks en un worktree desechable de HEAD en modo detached, con los cambios versionables sin commit superpuestos y sin ficheros gitignored. Consecuencias: la cifra no depende de la rama (antes, `session-init.sh` imprimía «Rama: main» en un push a main y la cifra subía a 143 > 142), ni de ficheros locales; los efectos de los hooks (marker de `cache-hygiene-hook.sh`, logs, `.scm/` derivado) no tocan la raíz, y no se borra nada de la raíz. Cada hook corre en su grupo de procesos y se espera a sus procesos en segundo plano (máximo 10 s; después se matan).
- `--hooks` aborta si un hook sale con código distinto de 0. No hay exclusiones.
- El reloj **no** está fijado: ningún hook lee una variable de reloj. Un hook cuya salida dependa de la fecha cambiaría la cifra de un día a otro; la doble ejecución solo lo detecta dentro del mismo minuto. Hoy ninguna salida medida depende de la fecha (los trabajos semanales y mensuales de `session-init.sh` van en segundo plano y a `/dev/null`).
- `session-init.sh` acota `focal-status.sh` a 0,5 s: con la máquina muy cargada la línea «Focal» puede salir como «timeout», más corta. La cifra bajaría (el trinquete pasa con aviso de baseline holgado), no subiría.

Los tokens de las filas partidas de `CLAUDE.md` son estimaciones por sección (`re.split('^## ')`); las filas de ficheros enteros son las medidas del script.
