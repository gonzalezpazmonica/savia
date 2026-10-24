---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L2
related_specs: [SE-442, SE-425, SE-450]
origin: triaje de code scanning (PR #1363), alertas #71-#104 Scorecard PinnedDependencies
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-465 — Dependencias de instalación sin fijar: imágenes, instaladores remotos, npm y pip

## Problema

Scorecard abre 34 alertas `PinnedDependenciesID` (#71-#104). SE-442 fijó las acciones `uses:` por
SHA y los requisitos de Python de la CI con hashes; estas 34 están fuera de lo que SE-442 tocó.
Medido sobre `main` (d941dc3a6) con `gh api …/code-scanning/alerts?state=open` y leyendo cada línea,
se agrupan en cinco causas:

| Grupo | Alertas | Qué hay | ¿Ejecuta código de terceros sin fijar? |
|---|---|---|---|
| G1 imágenes base | #71-#75 (5) | `FROM node:22-alpine` (`containment/Dockerfile.base`), `ubuntu:22.04` (`docker/savia-test/Dockerfile`), `python:3.11-slim` ×3 (`tests/pentest-lab/*/Dockerfile`) | Sí: la etiqueta puede cambiar de contenido |
| G2 instalador remoto por tubería | #76, #84, #89, #93 (4) | `curl … nodesource … \| bash` (savia-test), `curl ollama.ai/install.sh \| sh` (`emergency-setup.sh`, `savia-shield-setup.sh`), `curl opencode.ai/install \| bash` (`opencode-install.sh`) | Sí, el caso más grave: se ejecuta lo que sirva el dominio ese día |
| G3 falso positivo | #85-#88, #90-#92, #97 (8) | `curl` a una API (GitHub, Anthropic, Ollama local, DevTools local, ejemplo HTTP QUERY) cuya salida JSON va a `python3 -c "<código fijo>"` o `json.tool` | **No**: lo descargado es dato, no código |
| G4 npm | #77, #79-#83, #95, #96, #98, #99, #103, #104 (12) | (a) `npm install` donde hay lockfile versionado (`scripts/`: #79, #81, #104); (b) `npm install` sin lockfile versionado (`.opencode` #103, `savia-monitor` #82, `savia-web` #96, repo clonado de `ua-install.sh` #98/#99); (c) `npm install -g <paquete>` sin versión (#77, #80, #83, #95) | Sí en (b) y (c); en (a) el lock se respeta pero `npm install` puede reescribirlo |
| G5 pip | #78, #94, #100-#102 (5) | `pip install` sin hashes: pentest-lab (`-r requirements.txt`), `presidio-*` (`savia-shield-setup.sh`), `esptool mpremote` (`zeroclaw/setup.sh`), `pytest`, `pytest-json-report` y `deepeval` en `evals-ci.yaml` | Sí |

Dos hechos más:

- `.gitignore` ignora `**/package-lock.json` salvo `scripts/` y `projects/savia-vaults/` (SE-425).
  Los grupos G4(b) existen porque esos lockfiles se ignoran a propósito; SE-425 dejó web y monitor
  «al tocarlos» (su D2).
- G1 incluye el laboratorio de pentest, que es vulnerable a propósito en su código pero no tiene por
  qué serlo en su cadena de construcción.

## Valor y evidencia

G2 es ejecución remota de código en la máquina de quien instala, con la integridad delegada al
dominio. G1, G4(b-c) y G5 son el mismo riesgo atenuado (registro público, versión flotante). G3 no
tiene riesgo: se cierra con descarte razonado, no con cambio de código. Arreglar 26 alertas reales y
descartar 8 con causa sube la puntuación de Scorecard y, sobre todo, hace reproducible la instalación.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | G1: `FROM imagen:tag@sha256:<digest>` en los 5 Dockerfiles; el digest se resuelve con `docker buildx imagetools inspect` (o la API del registro) y Dependabot `docker` lo mantiene (se añade el ecosistema a `.github/dependabot.yml`). |
| S2 | G2: cada instalador remoto se sustituye por descarga de un artefacto versionado con verificación de SHA-256 antes de ejecutar (`curl -o` + `sha256sum -c`), o por el gestor de paquetes con versión fija (Node: imagen `node:<ver>` en vez de nodesource). Si el proveedor no publica artefacto con hash, se documenta y se deja la ruta remota detrás de una confirmación explícita (`--allow-remote-installer`, solo como argumento de línea de órdenes: sin equivalente en variable de entorno, y la CI lo rechaza). |
| S3 | G4(a): `npm ci` donde hay lockfile versionado. G4(c): `npm install -g <paquete>@<versión exacta>`. G4(b): decisión D1 por proyecto (versionar el lock como SE-425 o `npm ci` contra un lock generado en CI). |
| S4 | G5: `pip install --require-hashes -r <lock>` con locks generados por `pip-compile --generate-hashes` (mismo patrón que `.github/requirements/pip-audit.lock.txt` de SE-442). |
| S5 | Checker `scripts/check-pinned-installs.sh` que recorre `*.sh`, `Dockerfile*` y `.github/workflows/*` y falla ante `FROM` sin `@sha256:`, `curl … \| (ba)?sh`, `npm install -g` sin `@versión`, `npm install` sin `-g` (debe ser `npm ci`; cubre G4 a y b, con excepciones razonadas según D1) y `pip install` sin `--require-hashes`, con lista de excepciones razonadas en un fichero aparte. Trata también como ejecución de lo descargado `curl … \| python3` sin `-c "<literal>"` ni `-m json.tool` (`\| python3`, `\| python3 -`, `\| python3 /dev/stdin`). BATS con casos positivos y negativos. |
| S6 | G3: la PR deja en su body la orden `gh api -X PATCH …` de descarte (`false positive`) para las 8 alertas, con el motivo por alerta. No las descarta. |

## Fuera de alcance

- Fijar las dependencias **transitivas** de lo instalado (lo cubren los lockfiles).
- Vulnerabilidades conocidas en lo ya fijado: SE-466.
- Acciones `uses:` (SE-442, hecho).
- Descartar alertas: lo hace la operadora.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-check-pinned-installs.bats` pasa. |
| AC2 | Caso negativo: fixtures con `FROM python:3.11-slim`, `curl -fsSL x \| sh`, `npm install -g foo` y `pip install bar` hacen fallar el checker, con fichero y línea. Contra `main`, el checker sin excepciones reporta ≥ 26 hallazgos: G1 5 + G2 4 + G4 12 (a: `npm install` → `npm ci`; b: `npm install` sin lock; c: `-g` sin versión) + G5 5. Un fixture por patrón (`npm install` sin `-g` incluido) falla con fichero y línea. |
| AC3 | El checker **no** reporta los 8 casos de G3 (`curl … \| python3 -c`, `\| python3 -m json.tool`): test explícito, para que el falso positivo de Scorecard no se replique. Casos positivos simétricos que **sí** deben fallar: `curl x \| python3`, `curl x \| python3 -` y `curl x \| python3 /dev/stdin`. La excepción se limita a `python3 -c "<literal>"` y `python3 -m json.tool`. |
| AC4 | Tras S1-S4 (incluido `npm ci` donde hay lockfile) el checker sobre el repo da 0 hallazgos fuera de la lista de excepciones, y cada excepción lleva motivo. |
| AC5 | `bash install.sh` (o el smoke de `install-smoke.yml`) sigue verde en CI. |
| AC6 | En el siguiente análisis de Scorecard sobre `main` tras el merge, las alertas de G1, G2, G4 y G5 que se arreglaron pasan a `fixed` (comprobado con `gh api`); se anota en la spec el recuento antes/después. |

## Riesgos

- Digests y versiones fijas envejecen. Mitigación: Dependabot para `docker` y `pip`; para npm global
  y binarios con hash, una nota en el checker que avisa si el pin tiene más de N días (D2).
- Algunos proveedores (ollama, opencode) no publican hashes estables por plataforma. S2 lo resuelve
  con una ruta explícita y declarada, no con un pin falso.
- El checker por patrones textuales puede dar falsos positivos propios. AC3 fija el que ya conocemos.

## Esfuerzo

S1 S, S2 M, S3 S, S4 S, S5 M, S6 S. Total M.

## Decisiones pendientes de la operadora

- **D1**: `.opencode`, `savia-monitor`, `savia-web` y el repo de `ua-install.sh` — ¿versionar lockfile
  (como SE-425) o dejar `npm install` como excepción razonada? Propuesta: versionar en `.opencode`
  (la CI lo instala) y excepción para `ua-install.sh` (repo externo clonado).
- **D2**: antigüedad máxima de un pin manual antes de avisar (propuesta: 90 días).

## Referencias cruzadas

PR #1363 (triaje), SE-442 (acciones por SHA, requisitos con hashes, Dependabot), SE-425 (lockfiles
npm), SE-450 (instaladores aditivos e idempotentes), SE-466 (vulnerabilidades en dependencias).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Instaladores y Dockerfiles | independientes del frontend | los mismos |
| `.opencode/install.sh` (G4) | — | instalador del frontend OpenCode; mismo cambio que `install.sh` |
| Checker y BATS | independientes del frontend | los mismos |

### Verification protocol

- [ ] `install.sh` y `.opencode/install.sh` reciben el mismo cambio (hoy tienen la misma línea `npm install` en `scripts/`).
- [ ] El checker corre en `validate-ci-local.sh` sin depender del frontend.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: scripts, Dockerfiles y workflows; el único binding es el instalador de OpenCode, cubierto arriba.
