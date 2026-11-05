---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-04
author: Savia
phase: A
risk: L3
human_surface: true
related_specs: [SPEC-185, SPEC-181, SPEC-086, SPEC-189, SPEC-077, SE-335, SE-483, SE-487, SPEC-SE-091, SE-509, SE-505, SE-510]
origin: "Análisis comparativo Gentleman frente a Savia (2026-11-04, informe privado en Savia Labs) y decisión de la operadora del mismo día: Savia se especializa en investigación, metaorquestación y gobernanza; la programación se delega en harnesses aparte. Solo spec."
timeline:
  - from: "2026-11-04"
    learned: "2026-11-04"
    value: "PROPOSED"
---

# SE-511 — Contexto fijo por turno a la mitad o menos

## Problema (verificado en origin/main be2fca5aa, 2026-11-04)

Cada turno de Savia arranca cargando las mismas instrucciones, se usen o no: `CLAUDE.md`, sus 6 `@imports`, el perfil activo y el índice de memoria. El análisis medía unos 39 KB ≈ 10.900 tokens. Es coste en cada llamada y es ruido: una regla de proyectos de Azure DevOps viaja igual en una sesión de investigación. Con la especialización decidida el 2026-11-04 (investigación, metaorquestación y gobernanza; la programación va a harnesses aparte), buena parte de ese contexto fijo ya no es del día a día.

### Medidas recalculadas

| Pieza cargada en cada turno | Bytes | Caracteres | Comando |
|---|---|---|---|
| `CLAUDE.md` | 8.394 | 8.277 | `wc -c`, `wc -m` |
| — de ellos, la tabla «Lazy Reference» | 4.532 | | `re.split('^## ')` sobre `CLAUDE.md` (Apéndice A, B2) |
| `docs/critical-facts.md` | 1.058 | 1.034 | idem |
| `.claude/profiles/savia.md` | 6.680 | 6.581 | idem |
| `docs/rules/domain/radical-honesty.md` | 5.338 | 5.297 | idem |
| `docs/rules/domain/autonomous-safety.md` | 3.215 | 3.170 | idem |
| `docs/rules/domain/caveman-default.md` | 2.079 | 2.077 | idem |
| `docs/rules/domain/knowledge-discovery-priority.md` | 869 | 861 | idem |
| **Parte versionada** | **27.633** | **27.297** | `cat <los 7> \| wc -c` |
| Índice de memoria del frontend (fuera del repo, en la máquina de la operadora) | 7.350 | | `wc -c` |
| Perfil activo e índice de memoria externa (`.claude/profiles/active-user.md`, `.claude/external-memory/auto/MEMORY.md`) | no medible desde un worktree | | gitignored; existen solo en el checkout de cada operador |

En tokens: la parte versionada sale a **≈ 6.800** con la regla del repo (caracteres / 4, `scripts/token-estimator.sh:5`) y a **≈ 7.700** con la proporción del análisis (39 KB ≈ 10.900 tokens, 3,58 B/token). Sumando el índice de memoria, el total medido es **34.983 B ≈ 8.660–9.770 tokens** (límite inferior: (27.297 caracteres + 7.350) / 4, tomando los bytes del índice como cota de sus caracteres; superior: 34.983 B / 3,58), sin contar perfil activo, memoria externa ni lo que inyectan los 7 hooks de SessionStart y los 8 de UserPromptSubmit (`.claude/settings.json`, ver SE-510). Las dos proporciones difieren en un 13 %; por eso el objetivo se fija con **un** método versionado (D2), no con una cifra suelta.

### Qué ya existe (no se duplica, se enlaza)

| Pieza | Dónde | Qué cubre | Qué le falta |
|---|---|---|---|
| Anchor de 150 tokens | SPEC-185 (IMPLEMENTED), `docs/rules/domain/critical-facts-anchor.md:8-16`, `scripts/validate-critical-facts-cap.sh`, `scripts/generate-critical-facts.sh` | Tope duro para `critical-facts.md` | Solo ese fichero (85 tokens declarados); no mide el resto del contexto fijo. |
| Presupuesto L0-L3 | SPEC-181 (IMPLEMENTED), `scripts/audit-context-budget.sh:4,10` | L0+L1 ≤ 3.000 tokens según el `token_budget` **declarado** en el frontmatter de `docs/rules/domain/*.md`; hoy 2.879, «INVARIANT: OK» | Suma lo que dicen los ficheros de sí mismos, no lo que se carga: deja fuera `CLAUDE.md` (≈ 2.100 tokens) y `savia.md` (≈ 1.650), que juntos superan el resto. Por eso pasa con un contexto real de más del doble. |
| Lazy context | `CLAUDE.md:8` («6 @imports críticos… el resto bajo demanda»), tabla «Lazy Reference» | Carga diferida de 25 temas | La propia tabla pesa 4,5 KB en cada turno. |
| Presupuesto proactivo y selección | SPEC-086 (`scripts/context-budget-check.sh`), SPEC-189 (selector voraz), SPEC-077, `/context-budget` | Contexto **dinámico** de la sesión y de grafos | No tocan el contexto fijo de arranque. |
| Carga eager de la prioridad de descubrimiento | SE-335 (`docs/specs/SE-335-prioridad-descubrimiento-arranque.spec.md:33-37`) | Por qué `knowledge-discovery-priority.md` es import | Hay telemetría (`.claude/hooks/discovery-order-telemetry.sh:2-6`, SE-336 S3, modo sombra), no un gate. |
| Identidad canónica | SE-483, `.claude/profiles/savia.md` («Fuente única», `tests/test-se483-identity.bats`) | Frases canónicas de identidad | Se carga entera (6,7 KB) con ejemplos de alertas de sprint y tablas de tono. |
| Caveman siempre activo | SPEC-SE-091, `caveman-default.md` | Brevedad | Texto puro; sin enforcement. |
| Radical honesty | `radical-honesty.md` y `radical-honesty-enforcement.md:14-18` (capa 1, `sycophancy-strip.sh` con regex) | Prohibiciones y obligaciones | El enforcement no intercepta la respuesta final nativa (`radical-honesty.md`, § Enforcement). |
| Seguridad autónoma | `autonomous-safety.md`; hooks `block-commit-to-main.sh`, `block-force-push.sh`, `repeat-tool-guard.sh` (SE-445), `scripts/merge-sprint.sh` (SE-433) | Las prohibiciones de git ya tienen código | La regla en texto viaja igual en cada turno. |
| Medición de prompts | SE-509 (PROPOSED, PR #1481), experimento EXP-509 de Savia Labs: cumplimiento en casos trampa, sobreactivación en casos `golden`, tokens de entrada con Δ % frente a la línea base | Método e inventario de prompts de agentes | Ámbito: agentes, skills y reglas; el contexto de arranque del agente principal no es una de sus variantes. **SE-511 usa su método y su inventario; no repite ninguno.** |

## Lo que he entendido

### Escenas

1. Abres una sesión para revisar una línea de investigación. Savia sigue sabiendo quién es, habla en femenino, sin relleno y te dice lo que no quieres oír. Pero no ha cargado la cadencia del sprint ni las reglas de Azure DevOps: las lee si se las pides o si el turno lo necesita.
2. Una worker headless intenta hacer commit en `main`. No hace falta que lea `autonomous-safety.md`: el hook la para igual que hoy.
3. Tras el recorte, el informe de EXP-509 sobre el contexto de arranque muestra que el cumplimiento en los casos trampa bajó. El recorte se deshace con un revert y el informe dice qué pieza lo causó.
4. Ejecutas `bash scripts/context-fixed-measure.sh` y ves cuántos tokens viajan en cada turno, por pieza y en total, con el mismo número en tu máquina y en la CI para la parte versionada.

### Palabras de la persona

Pendiente: esta spec la redactó una worker sin acceso a la conversación de la operadora del 2026-11-04. Hay que copiar aquí, literal y con fecha, la frase de la operadora sobre la especialización de Savia.

### Qué SÍ será

- Un bloque compacto con identidad, tono y honestidad, y el resto bajo demanda.
- Un script que mide el contexto fijo real y un tope de 5.000 tokens que se comprueba en CI.
- Una regla que deja de cargarse como texto solo si antes tiene hook o script que la haga cumplir.

### Qué NO será

- No cambia la identidad de Savia (SE-483) ni sus principios: los compacta.
- No borra reglas: pasan de «se leen en cada turno» a «se leen cuando hacen falta».
- No se aprueba con la intuición de que «menos es mejor»: se aprueba con EXP-509.

### Confirmación

fecha: pendiente
respuesta: pendiente. La redactó una worker headless sin canal con la persona; antes de aprobar hay que enseñar las escenas por pregunta interactiva y copiar la respuesta literal (SE-505, PR #1476).

## Qué decide esta spec

### D1 — Bloque compacto

- Un único fichero de arranque (`docs/rules/domain/savia-core.md`, nombre a confirmar en S1) con: identidad canónica corta (frase de SE-483 tal cual, la comprueba `test-se483-identity.bats`), género gramatical, tono (prohibiciones de Radical Honesty y de caveman en una lista sin ejemplos), la **regla** de responder en el idioma del perfil activo (texto versionado; el **valor** del idioma lo aporta en tiempo de ejecución el perfil activo, que es gitignored y no entra en el bloque generado) y los gates inmutables de `critical-facts.md`.
- Los ficheros completos (`savia.md`, `radical-honesty.md`, `caveman-default.md`, `autonomous-safety.md`) **siguen existiendo** como fuente de verdad: el bloque compacto se **genera** de ellos (como `generate-critical-facts.sh`), no se redacta aparte. Así no hay dos textos que diverjan.
- `CLAUDE.md` queda en entrada, cierre, reglas 1-8 y un puntero a `docs/RESOLVER.md` en lugar de la tabla «Lazy Reference» de 4,5 KB.
- Se clasifica cada pieza que hoy se carga como **núcleo** (va en el bloque), **gate** (tiene enforcement por código y sale del texto fijo) o **bajo demanda** (se lee cuando el turno lo pide). La clasificación usa el inventario de SE-509a cuando exista; hasta entonces, una tabla en esta spec que S1 rellena.

### D2 — Medición reproducible

- `scripts/context-fixed-measure.sh`: resuelve los `@imports` de `CLAUDE.md` de forma recursiva, cuenta bytes, caracteres y tokens por pieza y en total, y en modo `--hooks` captura el `additionalContext` de los hooks de SessionStart y UserPromptSubmit.
- `--hooks` es reproducible por construcción: ejecuta los hooks registrados con una entrada fija versionada (`tests/fixtures/context-fixed/turn.json`: un prompt normal y un `session_id` fijo), `HOME` temporal vacío, sin perfil activo, sin red y con el reloj fijado por variable. Corre dos veces y, si las dos cifras difieren, sale con error (no se toma ninguna): un hook no determinista bajo la fixture se corrige o se excluye con motivo en la tabla de D1, nunca se promedia.
- Método de tokens versionado: por defecto, caracteres / 4 (el de `token-estimator.sh`); si hay credencial, también el recuento del endpoint de conteo de tokens del proveedor, y **el objetivo se juzga con el mayor** de los dos.
- Modos: `--versioned` (solo lo del repo; idéntico en CI y en cualquier máquina), `--hooks` (arriba; también idéntico en CI) y `--local` (añade perfil activo y memorias del operador, solo en local, sin escribir rutas ni contenido en la salida).
- Sustituye como invariante a la suma declarada de SPEC-181: `audit-context-budget.sh` sigue para los tiers, y el gate nuevo mide lo cargado.

### D3 — Objetivo

- **≤ 5.000 tokens** en `--versioned` + `--hooks` (las dos cifras deterministas de D2). En `--local`, informe sin gate (cada operador tiene un perfil distinto), con aviso si supera 6.000.
- Qué compara la CI: las dos cifras, cada una con su trinquete. `--versioned` se congela en `.ci-baseline/context-fixed-tokens.count` y `--hooks` en `.ci-baseline/context-fixed-hooks-tokens.count`; ninguna puede subir, como `capability-entropy.py`. La suma ≤ 5.000 se comprueba en el mismo paso.

### D4 — Validación con el método de EXP-509

- Variantes: A (contexto actual) y B (bloque compacto). Mismas métricas y corpus de casos trampa y `golden` que fija el prerregistro de EXP-509, ampliados con casos de arranque: idioma del perfil, género, rechazo de adulación, negativa a commitear en `main`, orden de descubrimiento, y casos de sobreactuación (por ejemplo, que no cite reglas de Azure DevOps en una sesión de investigación).
- Métricas: cumplimiento (% de casos trampa resueltos como manda la regla), sobreactuación (% de `golden` con comprobaciones o negativas innecesarias) y tokens de entrada con Δ % frente a A. En los dos modelos que use EXP-509.
- **Regla de decisión fijada antes de correr**: B se adopta si su cumplimiento no es peor que el de A dentro del margen que fije el prerregistro y la sobreactuación no sube. Si el cumplimiento baja, **se vuelve atrás** (revert del bloque y de `CLAUDE.md`) y se recorta por piezas.
- El registro va a Savia Labs como fase de EXP-509 o como experimento hermano con prerregistro propio. Si EXP-509 no ha cerrado, SE-511 espera: no se aprueba sin ese dato.

### D5 — Lo que deja de cargarse debe seguir cumpliéndose

- Una regla clasificada **gate** sale del texto fijo solo si existe un hook o script que la hace cumplir y un test que lo prueba con una entrada real. Ejemplos ya cubiertos: commit a `main` (`block-commit-to-main.sh`), push forzado (`block-force-push.sh`), tercera acción idéntica (`repeat-tool-guard.sh`), merge solo con `merge-sprint.sh`.
- Una regla sin enforcement por código **no sale**: o se queda en el bloque, o primero se le escribe el gate (spec aparte, escalera de remedios, `docs/rules/domain/remedy-ladder.md`).
- El hook tiene que correr con **todos** los perfiles de `/hook-profile`: si se salta en `minimal` (`profile_gate` por encima de `security`, `.claude/hooks/lib/profile-gate.sh:23-42`), la regla se quedaría sin texto y sin hook. Hoy `block-force-push.sh` es tier `security` y `block-commit-to-main.sh` y `repeat-tool-guard.sh` no llaman a `profile_gate`, así que los tres corren en todos los perfiles.
- `scripts/context-fixed-measure.sh --gates` lista las reglas que han salido del contexto y su hook; una sin hook, con hook ausente o con hook que algún perfil salta da FAIL.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-1 | `context-fixed-measure.sh --versioned` en main be2fca5aa da 27.633 B ± 0 y entre 6.800 y 7.800 tokens; dos ejecuciones dan la misma cifra. | positivo |
| AC-2 | Un `@import` que apunta a un fichero inexistente o un ciclo de imports → exit ≠ 0, nunca un total parcial como PASS. | negativo |
| AC-3 | Tras S2, `--versioned` + `--hooks` (fixture fija de D2) ≤ 5.000 tokens con el mayor de los dos métodos; dos ejecuciones de `--hooks` dan la misma cifra, y si difieren el script sale ≠ 0. | positivo / negativo |
| AC-4 | La CI falla si la cifra `--versioned` sube sobre `.ci-baseline/context-fixed-tokens.count` o la de `--hooks` sube sobre `.ci-baseline/context-fixed-hooks-tokens.count`. | negativo |
| AC-5 | El bloque compacto se regenera desde sus fuentes; editarlo a mano o cambiar una fuente sin regenerarlo falla su test de drift. | negativo |
| AC-6 | `test-se483-identity.bats` sigue en verde: la frase corta de identidad aparece literal en el bloque. | positivo |
| AC-7 | Sin `autonomous-safety.md` en el contexto fijo, un commit a `main`, un push forzado y la tercera llamada idéntica en rama `agent/*` siguen bloqueados por hook con **cada** perfil de `/hook-profile` (`minimal`, `standard`, `strict`, `ci`; tests que lo prueban con entrada por stdin y `SAVIA_HOOK_PROFILE` fijado). | negativo |
| AC-8 | Una regla marcada `gate` cuyo hook se borra, se desregistra o se salta con algún perfil (`profile_gate` por encima de `security`) hace fallar `--gates`. | negativo |
| AC-9 | El informe de validación (D4) tiene cumplimiento, sobreactuación y tokens por variante y modelo, con el commit medido. Sin él, la spec no pasa a APPROVED ni S2 se fusiona. | negativo |
| AC-10 | Si el cumplimiento de B cae por debajo del margen del prerregistro, el cambio se revierte en la misma PR o en la siguiente, y el informe lo registra. | negativo |
| AC-11 | `--local` no imprime rutas personales ni contenido del perfil, solo cifras por pieza (comprobado con `confidentiality-scan.sh`). | negativo |

## Fuera de alcance

- El contexto dinámico de la sesión (SPEC-086, SPEC-189) y la compactación.
- Los prompts de agentes, skills y comandos: los cubre SE-509.
- El coste de procesos de los hooks: SE-510. Aquí solo cuenta el texto que inyectan.
- Cambiar el contenido de la identidad o de los principios éticos.

## Riesgos

- **Pérdida de cumplimiento silenciosa.** Una regla que deja de leerse puede dejar de cumplirse sin que salte nada. Mitigación: D5 (solo sale lo que tiene gate) y D4 (medición antes de aprobar, revert si cae).
- **Ganancia ilusoria.** Si el modelo acaba leyendo bajo demanda lo mismo en casi cada turno, el ahorro desaparece. El informe de D4 cuenta también las lecturas bajo demanda por sesión.
- **Dos fuentes de identidad.** Mitigado con generación (AC-5) y la prueba de SE-483 (AC-6).
- **Recuento de tokens dependiente del método.** Mitigado con método versionado y el mayor de dos (D2).

## Plan por slices

1. **S0** — Prototipo para la persona: una sesión con el bloque compacto y otra con el actual, para que juzgue si «sigue siendo Savia» antes de medir (SE-505).
2. **S1** — Script de medición, línea base, trinquete y tabla núcleo/gate/bajo demanda (AC-1, AC-2, AC-4, AC-11).
3. **S2** — Bloque compacto generado y `CLAUDE.md` recortado, detrás de la validación D4 (AC-3, AC-5, AC-6, AC-7, AC-8, AC-9, AC-10).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `CLAUDE.md` y sus `@imports` | Cargados por el frontend en cada turno | `.opencode/CLAUDE.md` redirige al raíz; la medición cubre los dos puntos de entrada |
| Bloque compacto | `@import` desde `CLAUDE.md` | El mismo fichero, cargado desde la redirección |
| `scripts/context-fixed-measure.sh` | Bash + Python stdlib | El mismo |
| Inyección de hooks | SessionStart y UserPromptSubmit de `.claude/settings.json` | Guards `chat.message` de `savia-foundation.ts` (por ejemplo `learning-recall-guard.ts`), medidos igual |

### Verification protocol

- [ ] Funciona en runtime OpenCode: la medición resuelve también la redirección de `.opencode/CLAUDE.md`
- [ ] Tests BATS cubren medición, trinquete, drift del bloque y AC-7 en los dos motores
- [ ] No añade hooks nuevos; los gates de D5 ya existen o se crean en su propia spec

### Portability classification

- [x] **DUAL_BINDING**: los dos frontends cargan el mismo contexto y la medición debe cubrir ambos puntos de entrada.

## Apéndice A — Órdenes de medida

- B1: `wc -c` y `wc -m` de cada uno de los 7 ficheros versionados; `cat <los 7> | wc -c` → 27.633.
- B2: `python3` con `re.split(r'(?m)^## ', open('CLAUDE.md').read())` y `len(p.encode())` por sección → tabla «Lazy Reference» 4.532 B.
- B3: `bash scripts/audit-context-budget.sh` → «Eager (L0+L1): 2879 tokens (limit: 3000) INVARIANT: OK».
- B4: tokens = caracteres / 4 (`scripts/token-estimator.sh:5`) y bytes / 3,58 (proporción del análisis).

## Aprobación

Spec PROPOSED. Requiere el resultado de la validación D4 con el método de EXP-509 y la confirmación de escenas (SE-505). La aprueba la operadora o la orquestadora con autoridad delegada en su PR. Esta PR solo añade documentación.
