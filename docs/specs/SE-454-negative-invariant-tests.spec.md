---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: D
risk: L2
related_specs: [SE-453, SE-434, SE-444]
origin: output/research/20261020-learnings-zero-breach.md (A7, A8)
resource: https://github.com/interplains/zero-breach
---

# SE-454 — Invariantes negativos como tests sobre fuentes sensibles y aserción de red en analizadores

## Problema

Las invariantes de seguridad más importantes son negativas: «este módulo nunca imprime el valor del
secreto», «este analizador de contenido no confiable no abre sockets», «este servidor no lanza
procesos». Una refactorización o un agente que «mejora» el código puede romperlas sin que ningún test
positivo falle. Medido sobre `main` (2c54b4f63):

- Hay auditorías de política (`tests/test-hooks-blocking-audit.bats`,
  `tests/test-permissions-wildcard-audit.bats`) y tests de comportamiento de los guards, pero ningún
  test que recorra el código fuente de un componente sensible y falle ante un patrón prohibido.
- Los invariantes candidatos **se cumplen hoy**: `scripts/context-sanitize/normalize.py`,
  `scripts/context-sanitize/homoglyph-detect.py` y `scripts/extract-domain-entities.py` no importan
  `socket`, `urllib`, `http`, `requests`, `ssl` ni `subprocess`; `projects/savia-vaults/src/server/`
  no usa `child_process`; los mensajes de los guards `block-credential-leak.sh` son literales
  estáticos que no repiten el valor detectado. El test los fija, no arregla nada.
- Un invariante propuesto inicialmente es falso y se descarta: «`savia-gates` no usa red».
  `scripts/opencode-plugin/savia-gates/lib/shell-bridge.ts` usa `fetch` a propósito para hooks HTTP.

## Valor y evidencia

- zero-breach (Apache-2.0) fija con tests que su árbol de fuentes no lee valores cifrados de cookies
  ni invoca APIs de descifrado (para distinguirse de un infostealer), fija por literal su frase de
  cierre obligatoria (reescribir la constante rompe el test) y tiene un test de su guardia de red
  (lectura de los nombres y cabecera; no se ejecutó).
- Su guardia de red en proceso no es una frontera de SO y el propio proyecto lo dice. Para Savia la
  frontera real es el sandbox de SE-434 y `scripts/egress-gate.sh`; la guardia solo sirve como
  **aserción en tests** de analizadores de contenido no confiable. Presentarla como aislamiento daría
  falsa seguridad.
- No hay incidente propio medido; el valor es de regresión: barato (S a M) y en componentes donde un
  fallo es irreversible.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Ayudante de tests y primer lote de invariantes con AST (no regex): Python con `ast`, TypeScript con la API del compilador ya presente en `projects/savia-vaults` (`typescript`). Lote: (a) los tres analizadores Python no importan módulos de red ni `subprocess`; (b) `projects/savia-vaults/src/server/` no importa `child_process`; (c) los guards `block-*` no repiten en stderr el valor detectado (test de comportamiento con valor sintético construido en el test). |
| S2 | Cada invariante lleva un **caso negativo** (fixture que lo viola y el test lo detecta), según la regla 3 de `docs/rules/domain/checker-fail-closed.md`, y una línea que declara qué no demuestra (un invariante estático no prueba ausencia de la conducta). |
| S3 | Aserción de red en tests: fixture `no_network` de pytest que sustituye `socket.getaddrinfo`, `socket.create_connection` y `socket.socket.connect` y lanza `NetworkContactAttempt` con registro, aplicada a la suite de los analizadores de S1(a). Documentada como red de seguridad de pruebas, no como control. |
| S4 | Invariantes de componentes que aún no están en `main` (credenciales y broker del modo mediado de Space, lectura de cúpulas N3+): se añaden cuando exista el código, uno por PR, con el mismo formato. No se bloquea esta spec por ellos. |

## Fuera de alcance

- Tratar la guardia de red como control de seguridad o aislamiento.
- Tests basados solo en regex sobre código: frágiles; si un invariante no se puede expresar con AST ni
  con comportamiento, se documenta como no testeable.
- Tests de «doctrina» por literal de mensajes de usuario: no hay hoy un mensaje obligatorio cuya
  reescritura sea un riesgo identificado; se abre una spec o delta si aparece.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `python3 -m pytest tests/negative-invariants/test_no_network_imports.py` pasa: los tres analizadores de S1(a) no importan módulos de red ni `subprocess`. |
| AC2 | Caso negativo del mismo test: un fixture `tests/negative-invariants/fixtures/bad_import.py` con `import socket` hace fallar el chequeo y el test lo comprueba (`assert` de que el chequeo reporta el fichero y la línea). |
| AC3 | `cd projects/savia-vaults && npx vitest run tests/unit/negative-invariants.test.ts` pasa: ningún fichero de `src/server/` importa `child_process`; un fixture con `import { exec } from "child_process"` hace fallar el chequeo. |
| AC4 | `bats tests/test-guard-no-value-echo.bats` pasa: para `block-credential-leak.sh` con tokens sintéticos de GitHub, AWS y OpenAI construidos en el test, stderr contiene el aviso y **no** contiene el valor del token. |
| AC5 | Caso negativo de AC4: un guard de fixture que imprime el valor hace fallar el test. |
| AC6 | Con el fixture `no_network` activo, una llamada a `socket.create_connection(("example.invalid", 80))` dentro de un analizador lanza `NetworkContactAttempt` y deja registro; la suite de S1(a) pasa con el fixture activo (cero intentos). |
| AC7 | Cada test de invariante contiene una línea `# Lo que no demuestra:` (`grep -c` por fichero ≥ 1). |
| AC8 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- Falsa sensación de cobertura. Se declara por test (AC7) y la spec no promete ausencia de la conducta.
- Fragilidad ante reorganizaciones: los tests dependen de rutas. Mitigación: la lista de ficheros sale
  de una constante por test y falla con mensaje claro si la ruta desaparece (no pasa en vacío).
- Un test que pasa en vacío por glob sin ficheros sería el fallo abierto que esta spec intenta evitar:
  cada test exige al menos un fichero evaluado (`assert files`).

## Licencia de lo reutilizado

zero-breach es Apache-2.0, compatible con MIT. Se toma el patrón; la guardia de red (unas 90 líneas
allí) se reimplementa, no se copia.

## Esfuerzo

S1 S, S2 S, S3 S, S4 por demanda.

## Decisiones pendientes de la operadora

- **D1**: lista inicial de invariantes de S1 (propuesta: los tres descritos).
- **D2**: ubicación de los tests Python (propuesta: `tests/negative-invariants/`).

## Referencias cruzadas

SE-453 (contrato de resultado: sus casos negativos usan el mismo principio), SE-434 (frontera real de
red y sandbox), `docs/rules/domain/checker-fail-closed.md`, SE-444 (autoridad del verificador).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Tests de invariantes (S1 a S3) | BATS, pytest y vitest independientes del frontend | los mismos |
| Guards `block-*` (AC4) | hooks bash en `.claude/settings.json` | el mismo script invocado por `savia-gates` |

### Verification protocol

- [ ] Los tests corren sin frontend (no dependen de Claude Code ni de OpenCode).
- [ ] AC4 se ejecuta contra el script bash; si existe equivalente TypeScript del guard en `savia-gates`, se añade el mismo caso con la misma entrada.
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**: tests independientes del frontend; el único binding es el equivalente TypeScript de los guards, cubierto por el segundo punto.
