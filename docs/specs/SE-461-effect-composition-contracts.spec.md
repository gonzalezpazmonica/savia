---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L3
related_specs: [SE-454, SE-434, SE-436, SE-401]
origin: investigación de arquitectura agéntica 2026-09-25 a 2026-10-23 (entradas 12 y 27)
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-461 — Composición de efectos: combinaciones prohibidas en contratos de Yema y pruebas negativas

## Problema

Yema (ejecutora por contratos, repositorio propio) concede efectos **uno a uno**: `autoridad.efectos`
y `autoridad.prohibidos` sobre el vocabulario `leer, escribir, borrar, ejecutar, red, git-local,
git-remoto, fusionar, publicar, delegar, escribir-cupula`, y la puerta juzga cada llamada contra esa
lista. Leído en el repositorio de Yema (`docs/gobernanza.md`, `nucleo/contrato.py`,
`nucleo/puerta.py`) el 2026-10-23:

- El validador del contrato solo rechaza efectos desconocidos y efectos que estén a la vez en
  `efectos` y `prohibidos`. No hay ninguna regla sobre **combinaciones** (búsqueda de
  `compos|combina|incompatib` en el núcleo: una sola aparición, que trata órdenes de shell compuestas,
  no efectos).
- Combinaciones que hoy un contrato puede conceder sin aviso, cada efecto legítimo por separado:
  (1) `contexto.cupulas` con una cúpula N2+ **y** `git-remoto` o `publicar` sobre un repositorio
  público: lo leído puede acabar publicado; (2) cúpula N2+ **y** `red`; (3) `escribir` sobre rutas
  que otro sistema ejecuta (`.github/workflows/*`, hooks de git) **y** `git-remoto`: código ejecutado
  con secretos de CI; (4) `escribir` sobre ficheros que lee una orden permitida **y** `ejecutar`
  (el propio documento reconoce que `python3 -m unittest` ejecuta código del repo).
- La hipótesis H3 de la línea de investigación del metaharness (L39) prueba 10 familias
  de ampliación de autoridad, todas de **un** efecto fuera de contrato; ninguna de composición.

## Valor y evidencia

- Jung et al., «X-AgentRed», arXiv 2610.13886 (9-oct-2026): construye un grafo dirigido en el que los
  efectos de una herramienta satisfacen las precondiciones de otra y encadena peticiones benignas
  hasta resultados dañinos; en cuatro modelos frontera obtiene 1,77 veces la tasa de caminos dañinos
  del método de referencia STAC. Verificado (abstract).
- de la Chica Rodriguez et al., arXiv 2609.27994 (23-sep-2026): «no composicionalidad constitucional»,
  controles locales que no garantizan resultados colectivos aceptables. Verificado; es propuesta
  conceptual con simulaciones ilustrativas, se usa solo como marco.

## Alcance

La implementación vive en el repositorio de Yema y entra por PR en ese repositorio (rama `agent/*`
que fusiona la operadora). Esta spec fija el contrato; no toca código de Savia salvo la tabla común.

| Slice | Entrega |
|---|---|
| S1 | Tabla de combinaciones tóxicas versionada (`gobierno/composiciones.json` en Yema): cada entrada con `id`, `efectos` (y condiciones: nivel de cúpula, rutas ejecutables), `motivo` en lenguaje llano. Lote inicial: las cuatro del Problema. |
| S2 | Validación al aprobar: un contrato que concede una combinación de la tabla se rechaza salvo que declare `composiciones_aceptadas: [{id, motivo}]`; esa declaración entra en la huella sellada y se muestra en `yema resumen`. |
| S3 | Vigilancia en ejecución: la puerta guarda en el estado del contrato qué clases de efecto ya ocurrieron (p. ej. «leyó cúpula N2»); si la siguiente llamada completaría una combinación de la tabla no aceptada, responde «preguntar» con el motivo de la entrada, aunque el efecto individual esté concedido. |
| S4 | Pruebas negativas: una por entrada de la tabla, en estático (S2) y en secuencia (S3). Nueva familia 11 «composición» para H3 de L39, propuesta a Labs, no ejecutada aquí. |

## Fuera de alcance

- Grafo general de dependencias de herramientas ni búsqueda automática de caminos (X-AgentRed): solo
  una tabla explícita y revisable.
- Composición entre contratos distintos o entre agentes (ver SE-462 para transferencias).
- Efectos E4 (fuera de Yema en v0).

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `python3 -m unittest pruebas.test_composicion` (Yema): un contrato con cúpula N2 en contexto y `git-remoto` sin aceptación se rechaza al aprobar con el `id` y el motivo de la entrada. |
| AC2 | El mismo contrato con `composiciones_aceptadas` válida se aprueba, y cambiar el `motivo` después invalida la huella. |
| AC3 | Negativo secuencial: con un contrato que concede `leer` (cúpula N2) y `git-remoto` **aceptados por separado pero no como combinación**, la secuencia leer-cúpula → `git push` recibe «preguntar»; el push solo, sin lectura previa, se permite. |
| AC4 | Cada entrada de `composiciones.json` tiene al menos una prueba estática y una secuencial; un test recorre la tabla y falla si falta alguna (no pasa en vacío: exige ≥ 4 entradas). |
| AC5 | Negativo del propio test: una entrada nueva sin pruebas en un fixture hace fallar AC4. |
| AC6 | Los contratos sin ninguna combinación de la tabla se validan igual que hoy (suite actual de Yema en verde). |

## Riesgos

- Tabla incompleta: da confianza sobre lo que no lista. Se declara en `docs/gobernanza.md` como lista
  mínima, no como garantía.
- Más preguntas a la persona en S3. Cada una lleva el motivo (formato de SE-459).
- Estado de efectos ocurridos manipulable si la ejecutora alcanza el estado: vive junto al contrato,
  en la zona que la puerta ya protege.

## Decisiones de la operadora

- **D1**: lote inicial de combinaciones (propuesta: las cuatro del Problema).
- **D2**: en ejecución, ¿«preguntar» o «denegar» al completar una combinación no aceptada? (propuesta: preguntar).
- **D3**: ¿se acepta la familia 11 para H3 de L39 como trabajo de Labs?

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Validador y puerta de Yema | hook PreToolUse de Yema | el mismo núcleo Python vía el plugin de Yema, si existe; si no, sin binding |

### Verification protocol

- [ ] Las pruebas de Yema corren sin frontend.
- [ ] Si Yema tiene binding OpenCode, AC3 se repite con la misma entrada en ese binding.

### Portability classification

- [x] **PURE_BASH**: lógica en el núcleo Python de Yema, independiente del frontend.
