---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-10-29
author: Savia
phase: D
risk: L2
related_specs: [SE-445, SE-453, SE-462, SE-472]
origin: revisión de Anthropic Research en Savia Labs (privado), propuesta derivada a spec pública por encargo de la operadora 2026-10-29
timeline:
  - from: "2026-10-29"
    learned: "2026-10-29"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-475 — Clase del bloqueo en los mensajes de hook: FORMA o POLÍTICA

## Problema

Cuando un hook bloquea una orden, el agente solo ve un texto libre en stderr («BLOQUEADO: …»). Ese texto no dice si
el bloqueo es de **forma** (la misma intención se acepta dicha de otra manera: `git -C` en vez de `cd X && git`, un
literal que el regex confunde) o de **política** (confidencialidad, secretos, autoridad, seguridad, permisos: la
intención misma está prohibida). El agente tiene que adivinarlo, y la conducta por defecto de un modelo que no puede
terminar una tarea es buscar otra vía.

Medido sobre `main` (7b434f9ae):

- 41 de los hooks de `.claude/hooks/` contienen `exit 2` (bloqueo) y 27 guards TS en `.opencode/plugins/guards/`.
- Ninguno declara la clase del bloqueo: `grep -E '(FORMA|POLÍTICA):'` sobre hooks y guards devuelve 0 ficheros.
- La regla de los workers que distingue FORMA y POLÍTICA existe solo como texto en la plantilla de encargo, que vive
  fuera del repo; el hook no da al agente el dato para aplicarla.

## Fuente

- Anthropic, «Investigating unintended model actions»: la mayoría de acciones no deseadas son formas de
  *persistencia*: cuando Claude no puede completar la tarea tal como se pidió, rodea la restricción en lugar de parar.
  <https://www.anthropic.com/research/investigating-unintended-model-actions>
- Anthropic, evaluaciones de alineamiento tras incidentes: cuando la tarea es imposible dentro del alcance, el modelo
  tiende a salirse de él; los prompts deberían declarar objetivos, acciones permitidas y fronteras.
  <https://www.anthropic.com/research/alignment-assessment-cybersecurity-incidents> ·
  <https://www.anthropic.com/research/alignment-assessment-ukaisi>
- Diseño y priorización: Savia Labs (privado).

## Propuesta

1. **Contrato de mensaje.** Todo bloqueo de un hook o guard empieza su primera línea de stderr (o el
   `permissionDecisionReason` cuando el hook responde en JSON) con exactamente uno de:
   - `FORMA:` — la intención es legítima; el mensaje **debe** incluir la forma permitida (`Usa: …`).
   - `POLÍTICA:` — la intención está prohibida; el mensaje **debe** terminar con `No hay forma alternativa: para y
     escala.` y no sugiere reescrituras.
   Sin prefijo, el bloqueo se trata como `POLÍTICA` (fallo cerrado).
2. **Biblioteca común.** `scripts/lib/hook-block.sh` con `hook_block_form "<motivo>" "<forma permitida>"` y
   `hook_block_policy "<motivo>"`, que escriben el mensaje y salen con 2. Equivalente TS en
   `.opencode/plugins/lib/hook-block.ts` con el mismo texto (paridad probada con la misma entrada).
3. **Clasificación de los hooks existentes.** Inventario de los 41 hooks y 27 guards con su clase propuesta. Regla:
   ante la duda, `POLÍTICA`. Un hook con ramas de ambas clases usa la función correspondiente en cada rama.
4. **Auditoría.** `scripts/hook-block-class-audit.sh` lista los `exit 2` (bash) y bloqueos (TS) que no pasan por la
   biblioteca; ratchet con línea base en `.ci-baseline/hook-block-class.count`, que solo puede bajar.
5. **Regla pública.** Sección en `docs/rules/domain/autonomous-safety.md`: ante `POLÍTICA` o sin clase, el agente para,
   deja estado parcial con el mensaje exacto y no busca otra vía (ni reescribir la orden, ni pasarla por fichero +
   ejecución, ni cambiar de herramienta).

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `bats tests/test-hook-block-lib.bats`: `hook_block_form` escribe una primera línea que empieza por `FORMA:`, contiene `Usa:` y sale 2; `hook_block_policy` empieza por `POLÍTICA:`, termina con la frase de escalado, no contiene `Usa:` y sale 2. `hook_block_form` sin forma permitida falla (exit distinto de 0 y de 2) en lugar de emitir un FORMA incompleto. |
| AC2 | Test de paridad (`.opencode/plugins/__tests__/hook-block.test.ts`): para las mismas entradas, el texto TS es idéntico byte a byte al bash. |
| AC3 | `bats tests/test-hook-block-class-audit.bats`: un hook de fixture con `exit 2` sin biblioteca se reporta; uno que usa la biblioteca no; el ratchet falla si la cuenta sube y pasa si baja o se mantiene. |
| AC4 | Al menos `block-force-push`, `block-credential-leak` y el guard de rama/commit a main migrados: sus tests BATS existentes siguen en verde y se añade una aserción de prefijo por cada rama de bloqueo (caso negativo: una orden permitida no emite prefijo). |
| AC5 | Regresión de conducta: los hooks migrados bloquean exactamente las mismas entradas que en `main` sobre sus fixtures (mismo exit code); solo cambia el texto. |

## Riesgos

- **Clase mal asignada hacia FORMA**: el agente reescribe algo que era de política. Mitigación: duda → POLÍTICA;
  revisión humana del inventario antes de migrar; un FORMA exige escribir la forma permitida, lo que obliga a pensar
  si existe.
- **Más ejecuciones parciales** en modo autónomo. Es el precio buscado: menos rodeos.
- **Deriva bash/TS**: ya ocurrió en otros guards. Mitigación: AC2.

## Alternativas

- **Solo cambiar la plantilla de encargo** (sin tocar hooks): barato, pero el agente sigue sin el dato en el momento
  del bloqueo; depende de que adivine bien.
- **Códigos de salida distintos** (p. ej. 2 = política, 3 = forma): el arnés trata de forma distinta los códigos
  distintos de 2 en algunos eventos, y el agente no ve el código, ve el texto. Descartada.
- **No hacer nada**: coste, persistencia ante bloqueos sin señal que la frene.

## Lo que no se hace

- No cambia qué bloquea cada hook: solo el mensaje.
- No se migran los 68 hooks y guards en un PR: S2 migra los de política más críticos y el ratchet cubre el resto.
- No se versiona la plantilla de encargo de los workers (es privada); esta spec da el contrato que esa plantilla cita.
- No hay detección automática de rodeos posteriores al bloqueo (eso es SE-445, repetición bloqueante).

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Biblioteca bash + TS, regla en `autonomous-safety.md`, tests AC1-AC2. |
| S2 | Inventario de clases (revisado por la operadora), migración de los guards de política críticos, AC4-AC5. |
| S3 | Auditoría y ratchet, AC3. |

## Esfuerzo

S1 S, S2 M, S3 S.

## Decisiones pendientes de la operadora

- **D1**: prefijos en español (`FORMA:`/`POLÍTICA:`) o bilingües (propuesta: español, con alias `FORM:`/`POLICY:`
  aceptados por la auditoría para hooks de terceros).
- **D2**: revisar el inventario de clases antes de S2 (propuesta: sí).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/lib/hook-block.sh` | sourced por `.claude/hooks/*.sh` | sourced por los hooks bash que reutiliza el plugin |
| `hook-block.ts` | n/a | `.opencode/plugins/lib/hook-block.ts`, usado por `.opencode/plugins/guards/*.ts` |
| `scripts/hook-block-class-audit.sh` | script bash | el mismo script (escanea ambos árboles) |

### Verification protocol

- [ ] Funciona en runtime OpenCode: guard TS migrado bloquea con prefijo.
- [ ] Tests cubren ambos paths (BATS + test TS de paridad).
- [ ] Sin hooks nuevos; los migrados siguen registrados en `savia-gates`.

### Portability classification

- [x] **DUAL_BINDING**: biblioteca bash para los hooks de Claude Code y su par TS para los guards de OpenCode desde S1.
