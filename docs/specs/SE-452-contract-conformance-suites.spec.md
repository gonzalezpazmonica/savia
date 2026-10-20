---
status: PROPOSED
priority: P3
developer_type: agent-single
created: 2026-10-20
author: Savia
phase: C
risk: L2
related_specs: [SE-429, SE-443, SE-384, SE-369, SPEC-155]
origin: output/research/20261020-learnings-inditex.md (L5)
resource: https://github.com/InditexTech/kumoss
---

# SE-452 — Suite de conformidad ejecutable publicada junto a cada contrato de interoperabilidad

## Problema

SE-429 define la interoperabilidad de Savia Space (REST con contrato OpenAPI 3.1, MCP y A2A) y ya
prevé una suite de escenarios común a los tres adaptadores. Esa suite sirve para probar **nuestra**
implementación. Un tercero que escriba un cliente, un servidor compatible o un conector no tiene
forma de comprobar si cumple el contrato sin leer el código ni la spec.

`docs/rules/domain/external-contract-testing.md` (SPEC-155) fija la regla inversa: nuestros módulos que
dialogan con un sistema externo se prueban con la forma literal documentada por ese sistema. Falta la
mitad simétrica: lo que publicamos como contrato debería ir acompañado de la prueba que lo hace
verificable desde fuera. Hoy el único `openapi.yaml` del repo es el de Savia Bridge
(`scripts/openapi.yaml`, contrato móvil → CLI), sin suite de conformidad asociada.

## Valor y evidencia

- Kumoss (Inditex Tech) define cuatro contratos en `contracts/openapi/` (IaC, notificaciones, mapeo
  de repositorios, autorización) y, en `contracts/conformance/`, una suite por contrato que cualquier
  implementación ajena puede ejecutar. Cada punto de extensión es un sidecar tras un contrato y el
  núcleo no conoce la implementación. La aportación nueva no es el contrato, es que «cumplir el
  contrato» pasa a ser **verificable por terceros**.
- Encaja con la dirección de Space (SE-429, SE-443 para conectores): cuantos más clientes y
  conectores ajenos, más barato es tener una prueba pública que una revisión humana de cada uno.
- Evidencia débil para Savia hoy: no hay implementadores externos conocidos. Por eso la prioridad es
  baja y el alcance es un piloto sobre un único contrato.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Piloto sobre **un** contrato (propuesta: el de la API REST de Space cuando exista congelado, o el de Savia Bridge como ensayo): directorio `conformance/<contrato>/` con casos ejecutables contra una URL base (`BASE_URL=… bash conformance/run.sh`), sin depender del código de Savia. |
| S2 | Cada caso lleva identificador estable, el fragmento del contrato que comprueba y un resultado `pass`/`fail`/`skip` con motivo (un `skip` por autoridad no disponible se nombra, ver SE-444). Informe en JSON y en texto. |
| S3 | La suite se ejecuta en CI contra la implementación de Savia y falla si la implementación deja de cumplir el contrato o si el contrato cambia sin cambiar la suite (`scripts/contract-pin.sh`, SE-369). |
| S4 | Decisión de generalizar al resto de contratos (MCP, A2A) tras evaluar el coste de mantenimiento del piloto. |

## Fuera de alcance

- Certificar implementaciones de terceros ni publicar una marca de conformidad.
- Herramientas generativas de pruebas de propiedades en esta spec (la elección entre hurl, schemathesis
  o BATS puro es parte de S1 y se justifica allí).
- Cambiar el contrato: la suite lo verifica, no lo redefine.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `BASE_URL=<mock> bash conformance/<contrato>/run.sh` termina en 0 contra un servidor de referencia que cumple el contrato, y en distinto de 0 contra una variante defectuosa (campo obligatorio ausente en una respuesta) con el caso fallido nombrado. |
| AC2 | Cada caso tiene identificador (`CF-<contrato>-NNN`) y referencia al fragmento del contrato; `grep` sobre el directorio no encuentra casos sin ambos. |
| AC3 | `skip` siempre lleva motivo no vacío; un caso sin motivo hace fallar la validación de la propia suite. |
| AC4 | Cambiar un tipo en el contrato OpenAPI sin tocar la suite hace fallar el job de CI (`scripts/contract-pin.sh`, SE-369). |
| AC5 | La suite no importa código de Savia: `grep -r "scripts/lib" conformance/` sin resultados. |
| AC6 | `capability-entropy.py --check` PASS y `validate-ci-local.sh --quick` verde. |

## Riesgos

- Mantenimiento doble contrato/suite: por eso se empieza por uno y S4 es una decisión con datos.
- Una suite que solo prueba el camino feliz da falsa seguridad: los casos negativos son parte de AC1.
- Prematuro si el contrato todavía se mueve: la suite se publica con el contrato congelado, no antes.

## Licencia de lo reutilizado

Solo el patrón de organización (contrato más suite). Kumoss es Apache-2.0, compatible con MIT. La
herramienta que se elija en S1 se declara con su licencia en la spec delta o en el README de la suite.

## Esfuerzo

S1 M, S2 S, S3 S, S4 decisión.

## Decisiones pendientes de la operadora

- **D1**: qué contrato es el piloto, y si se espera a que el de Space esté congelado.
- **D2**: si la suite se publica como paquete independiente o dentro del repositorio.

## Referencias cruzadas

SE-429 (interop), SE-443 (conectores MCP), SE-384 (evaluación propia), SPEC-155 (pruebas de contratos
externos, regla inversa), SE-444 (skips nombrados por autoridad).

## OpenCode Implementation Plan

### Bindings touched

Ninguno: la suite es independiente del frontend por diseño.

### Verification protocol

- [ ] Se ejecuta igual con Claude Code y con OpenCode (no los invoca).
- [ ] Sin hooks nuevos.

### Portability classification

- [x] **PURE_BASH**
