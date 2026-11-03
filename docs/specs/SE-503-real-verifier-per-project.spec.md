---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-03
author: Savia
phase: A
risk: L2
related_specs: [SE-144, SE-351, SE-444, SE-476, SE-490, SE-494, SPEC-064, SE-398]
resource: https://github.com/cursor/plugins/blob/main/pstack/skills/create-verification-skill/SKILL.md
origin: "Informe de investigación sobre 115 números de la newsletter The Code (archivado en SaviaLabs, labs/research/20261103-the-code-oportunidades.md), propuesta 2. Adoptada por la orquestadora con autoridad delegada de la operadora. Solo spec."
timeline:
  - from: "2026-11-03"
    learned: "2026-11-03"
    value: "PROPOSED"
---

# SE-503 — Verificador real por proyecto

## Problema (verificado en origin/main 2acce7c37, 2026-11-03)

Savia sabe ejecutar suites que alguien ya escribió y sabe mirar capturas, pero no tiene una forma reutilizable de **comprobar que un proyecto hace lo que dice en el entorno donde se usa**. El resultado es que hay entregas que pasan la CI y fallan en el sitio real, y la lista de lo que falta probar vive en un README como prosa manual.

Dos casos actuales:

1. **App Android de Savia Space (Continuidad).** Su README de Continuidad (repo privado de Space) tiene una sección «Pendiente de probar en un dispositivo real» con **10 comprobaciones manuales** (servicio en primer plano por versión de Android, Doze, reinicio, pantalla de bloqueo, R8, lector de pantalla…). La décima es el caso tipo: el centinela del bloqueo de pantalla vive en el Keystore de Android y **Robolectric no tiene Keystore**. La suite JVM de la CI prueba la especificación y la lectura de errores y pasa; el comportamiento real (quitar el PIN invalida el emparejamiento) solo se vio el 2026-11-03 en un emulador Android 15 con un guion `adb` escrito a mano para ese caso, y sigue sin probar en un móvil con Keystore en TEE.
2. **Soul (CLI de `projects/soul-continuity`).** Su punta a punta (`projects/soul-continuity/test/e2e.test.ts:1-5`) corre contra un doble HTTP local y un **doble de `secret-tool`**. La prueba en teléfono real es una guía manual con casillas OK/FALLO (`projects/soul-continuity/docs/prueba-dispositivo.md:1`, bloques en `:28`, `:83`, `:107`, `:124`). Nada ejecuta la CLI instalada contra el almacén de credenciales real del sistema.

## Discovery: qué ya existe (sección 12 del informe)

| Pieza | Dónde | Qué cubre | Qué no cubre |
|---|---|---|---|
| Web E2E con Webwright | SE-144 (APPROVED), `docs/specs/SE-144-web-e2e-webwright-patterns.spec.md:23-37`; implementado en `.claude/agents/web-e2e-tester.md:50-68` (fases 3a–3d, `output/web-tasks/<id>/`) | Bucle escribir → ejecutar → inspeccionar → reparar, script reutilizable por tarea, capturas | Solo web; la autorreflexión la hace el **mismo modelo** que ejecuta (`web-e2e-tester.md:104`); no descubre cómo arrancar el proyecto ni liga la evidencia a commit y spec. |
| Suite Playwright | `projects/savia-web/playwright.config.ts`, `projects/savia-monitor/playwright.config.ts`; fase 2 del agente (`web-e2e-tester.md:38-41`) | Regresión web existente | Otras superficies. |
| QA visual | `.claude/commands/visual-qa.md:1-3`, agente `visual-qa-agent` | Comparar capturas con diseño | Una captura no prueba un efecto persistente. |
| Computer Use QA | SPEC-064 (PROPOSED), `docs/propuestas/SPEC-064-computer-use-integration.md:31,41-45` | QA visual en contenedor | Excluye el control de escritorio real y no sustituye a Playwright. |
| Superficies de runtime | SE-398 (`docs/specs/SE-398-desktop-runtime-surface-support.spec.md`) | Qué frontends existen (CLI, TUI, Desktop) | No es verificación de proyectos. |
| Android | Skill `android-autonomous-debugger` (`.claude/skills/android-autonomous-debugger/SKILL.md:21-25`), `scripts/adb-run.sh` | Instalar, lanzar, logcat, capturas contra un dispositivo | No hay contrato de verificación ni feature-map; cada caso se escribe a mano. |
| Autoridad del verificador | SE-444 (APPROVED), `docs/rules/domain/ac-verifier-authority.md:9-19` | Valores `real`, `simulada`, `estatica`; un AC que exige comportamiento real no cierra con un doble | No dice **cómo** producir evidencia `real`. |
| Independencia | SE-476 (PROPOSED), `docs/specs/SE-476-verification-independence-labels.spec.md:57-61` | Marca `verifier` y `author`; la autorrevisión es higiene | No crea el verificador independiente. |
| Binario y reproducible | SE-351, `docs/specs/SE-351-poc-verify.spec.md` | Veredicto por señal observable, no por juicio del agente | Solo pentest. |
| Trazas a regresiones | SE-494, PR #1453 (PROPOSED) | Fallos congelados como casos herméticos | Lo hermético no prueba el entorno real; es lo complementario. |
| Evaluaciones | Skill `evaluations-framework` (G-Eval) | Calidad de outputs de agentes | No es verificación funcional de un proyecto. |

**Recorte que hace el discovery.**

- La **regla de autoridad** (`real` / `simulada` / `estatica`) ya existe en SE-444: esta spec la consume, no define otra.
- La **etiqueta de independencia** ya está en SE-476: esta spec exige el dato y lo produce, no crea otra etiqueta.
- El **bucle web** de SE-144 se reutiliza como el `Drive` de la superficie web; no se reimplementa.
- Fuera: QA visual (ya cubierta), Computer Use de escritorio (SPEC-064, y la propuesta 5 del informe queda aplazada), regresiones herméticas (SE-494).

Lo que queda y esta spec decide: un **contrato común por proyecto**, un **feature-map** con casos negativos, la regla de que el generador **ejecuta** el recorrido antes de declararse listo, y la **evidencia ligada a commit y spec** con autoridad SE-444.

## Qué decide esta spec

### Contrato de verificador (`verifier/1`)

Cada proyecto verificable tiene `projects/<p>/verify/verifier.yaml` (o `verify/` en la raíz de un repo propio) y los scripts que nombra. Cinco fases, cada una un ejecutable con exit estable:

| Fase | Hace | Salida |
|---|---|---|
| `Launch` | Arranca lo necesario (instalar APK, `soul init`, servidor) y espera *readiness* con un tiempo máximo | `READY` / `NOT_READY` + motivo |
| `Doctor` | Diagnóstico sin efectos: herramientas, dispositivo, versiones, permisos | `OK` / `MISSING:<qué>` |
| `Drive` | Recorre el feature-map como lo haría una persona: toques, órdenes, peticiones | por caso `PASS` / `FAIL` / `INCOMPLETE` |
| `Evidence` | Recoge acciones, estados observados, efectos externos y marcas de tiempo | `evidence.json` + artefactos |
| `Cleanup` | Desmonta (desinstala, borra datos de prueba) **sin borrar la evidencia** | `CLEAN` / `DIRTY:<qué queda>` |

Resultado global: `PASS` solo si `Doctor` = OK, `Launch` = READY, todos los casos obligatorios = PASS y la evidencia existe tras `Cleanup`. Falta de herramienta o de dispositivo → `BLOCKED`. Cualquier otro error o salida no interpretable → `UNKNOWN`. Ninguno de los dos da exit 0.

### Feature-map

`verify/feature-map.yaml`: una entrada por capacidad observable, sacada de rutas, comandos, pantallas o APIs.

| Campo | Contenido |
|---|---|
| `id` | estable |
| `surface` | `android`, `cli`, `web`, `api`, `tui`, `desktop`, `library` |
| `entry` | dónde empieza (pantalla, orden, ruta) |
| `action` | qué hace la persona |
| `expected` | estado observable esperado |
| `negative` | **obligatorio**: la condición en la que debe fallar o negarse, y cómo se observa |
| `effects` | efectos externos esperados (fichero, credencial, notificación, red) y si son reales o simulados |
| `authority_required` | `real` o `simulada`, con el vocabulario de SE-444 |
| `spec_ref` | spec y AC que cubre |

Una entrada sin `negative` invalida el fichero.

### El generador ejecuta antes de declararse listo

`scripts/verifier-gen.sh <proyecto>` analiza el repo (manifiestos, `package.json` `bin`, `build.gradle*`, rutas web), propone `verifier.yaml` y `feature-map.yaml`, y **ejecuta** al menos un recorrido completo `Launch → Doctor → Drive (1 caso positivo y su negativo) → Evidence → Cleanup`. Si no lo ejecutó o falló, el verificador queda `status: DRAFT` y no puede usarse como evidencia. Solo pasa a `status: READY` con un `evidence.json` de ese recorrido.

### Evidencia

`output/verify/<proyecto>/<commit_corto>-<fecha>/evidence.json` con: `commit` (SHA completo del árbol probado), `spec_ref`, `surface`, `authority` (`real` si se usó el entorno real; `simulada` si cualquier efecto declarado se simuló), `environment` (por ejemplo `android-emulator-api35`, `android-device`, sin número de serie ni datos de la persona), `verifier_identity` y `author_identity` (SE-476), casos con resultado y marcas de tiempo, y hash de cada artefacto. Si el árbol tiene cambios sin commit, `authority` no puede ser `real` y el resultado es `UNKNOWN`.

### Independencia

El verificador lo genera y ejecuta una sesión distinta de la que implementó el cambio. Si `verifier_identity == author_identity`, la evidencia se marca `self` y no cierra un AC (SE-476). Un mock nunca prueba un efecto externo declarado como real.

## Casos obligatorios

1. **Android de Space en dispositivo o emulador real.** Verificador para la app de Continuidad que cubra, al menos, el centinela del bloqueo (atar con PIN → bloquear, desbloquear, reiniciar → quitar PIN y poner otro → el emparejamiento se pierde), con su negativo (sin quitar el PIN, el resultado esperado de «perdido» debe fallar). Debe demostrar el caso que hoy pasa CI y falla o no se prueba en dispositivo: la suite JVM en verde no basta y el verificador lo dice. En emulador, `authority: real` solo para lo que el emulador implementa de verdad; el Keystore por software del emulador se anota en `environment` y no cierra un AC que exija TEE.
2. **Soul (CLI).** Verificador que instala la CLI en un directorio temporal de usuario, ejecuta `init → login (fuente de prueba) → serve → pair → consulta → unpair → uninstall` contra el almacén de credenciales real del sistema cuando existe, y comprueba que tras `uninstall` no queda estado ni credencial. Su negativo: un token desemparejado deja de valer.

## Criterios de aceptación

| AC | Criterio | Tipo |
|---|---|---|
| AC-1 | `verifier.yaml` y `feature-map.yaml` tienen esquema validado por `scripts/verifier-validate.py`; una entrada sin `negative` da exit 2. | negativo |
| AC-2 | El generador sobre Soul produce un verificador `READY` con un `evidence.json` del recorrido que él mismo ejecutó. | positivo |
| AC-3 | Si el recorrido del generador falla (por ejemplo, `Launch` con un binario inexistente), el verificador queda `DRAFT` y `verifier-run.sh` se niega a usarlo como evidencia (exit ≠ 0). | negativo |
| AC-4 | Verificador Android de Space ejecutado en un emulador o dispositivo: el caso del centinela pasa en las tres etapas y su negativo falla como debe. La evidencia registra `environment` y `authority`. | positivo |
| AC-5 | Demostración de la diferencia: en el mismo commit, la suite JVM de la app pasa y el verificador informa la etapa que la JVM no puede comprobar (o la falla, si se introduce el defecto). Se documenta con los dos resultados. | positivo |
| AC-6 | Sin dispositivo ni emulador (`adb devices` vacío o `adb` ausente), el verificador Android sale `BLOCKED`, nunca `PASS`. | negativo |
| AC-7 | Sin `secret-tool` o equivalente, el verificador de Soul marca los casos de credenciales `BLOCKED` o `authority: simulada` y no cierra un AC que pida `real`. | negativo |
| AC-8 | Evidencia ligada: `commit` coincide con `git rev-parse HEAD` del árbol probado; con cambios sin commit el resultado es `UNKNOWN`. | negativo |
| AC-9 | La evidencia persiste tras `Cleanup` y su hash coincide; `Cleanup` que deja restos informa `DIRTY`. | positivo / negativo |
| AC-10 | Drift: si una entrada del feature-map apunta a una orden, pantalla o ruta que ya no existe, `Drive` da `FAIL` con `DRIFT:<id>`, no `PASS`. | negativo |
| AC-11 | Si `verifier_identity == author_identity`, la evidencia se marca `self` y la función de listado de SE-444/SE-476 la trata como no independiente. | negativo |
| AC-12 | Una salida no interpretable de cualquier fase da `UNKNOWN` y exit ≠ 0. | negativo |
| AC-13 | Ningún fichero de evidencia ni de verificador contiene rutas personales, números de serie, IP ni datos de la persona (comprobado por `confidentiality-scan.sh`). | negativo |

## Portabilidad

- El contrato es por fichero, independiente del frontend.
- Las fases reutilizan lo que ya hay: Playwright (web, vía SE-144), `scripts/adb-run.sh` (Android), PTY o subproceso (CLI), `curl` (API). No se añade ningún producto nuevo.
- Multioperador: nada del verificador conoce a la persona; el dispositivo se elige por variable (`SAVIA_VERIFY_DEVICE`) y no se versiona.
- Repos privados (como Space): el verificador vive en ese repo; Savia solo aporta contrato, generador y validador.

## Fuera de alcance

- Control del escritorio real (SPEC-064 lo excluye; propuesta 5 del informe aplazada).
- Sustituir la CI o las suites existentes: el verificador las complementa.
- Probar un móvil de cada fabricante: el AC-4 pide uno; el resto queda como deuda nombrada.
- Publicar evidencia fuera de la máquina.

## Riesgos

- **Captura como prueba**: una captura no demuestra un efecto persistente. El feature-map obliga a declarar el efecto y cómo se observa.
- **Dispositivo compartido**: el guion del centinela cambia el PIN; solo emulador o móvil de pruebas sin bloqueo previo, y `Doctor` lo comprueba antes.
- **Coste de mantenimiento**: el feature-map deriva. AC-10 lo convierte en un fallo visible.
- **Autoridad sobrevalorada**: emulador ≠ dispositivo. `environment` lo hace explícito y SE-444 decide qué cierra.

## Plan por slices

1. **S1** — Esquemas, validador, `verifier-run.sh` con los resultados `PASS`/`FAIL`/`BLOCKED`/`UNKNOWN` y evidencia ligada (AC-1, AC-8, AC-9, AC-12, AC-13).
2. **S2** — Generador con recorrido obligatorio y `DRAFT`/`READY`; verificador de Soul (AC-2, AC-3, AC-7, AC-10, AC-11).
3. **S3** — Verificador Android de Space en su repo, con el contrato de Savia (AC-4, AC-5, AC-6).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/verifier-gen.sh`, `verifier-run.sh`, `verifier-validate.py` | Bash y Python stdlib desde la sesión | Los mismos |
| `projects/soul-continuity/verify/*` | Ficheros y scripts del proyecto | Los mismos |
| `tests/test-verifier-*.bats` | BATS | BATS |

### Verification protocol

- [ ] Funciona en runtime OpenCode: los scripts no dependen del frontend
- [ ] Tests BATS cubren cada resultado y cada negativo
- [ ] No añade hooks

### Portability classification

- [x] **PURE_BASH**: bash y Python stdlib; `adb`, Playwright y el almacén de credenciales son opcionales y su ausencia da `BLOCKED`.

## Aprobación

Spec PROPOSED. La aprueba la operadora o la orquestadora con autoridad delegada en su PR. Esta PR solo añade documentación; ningún agente la fusiona sin grant.
