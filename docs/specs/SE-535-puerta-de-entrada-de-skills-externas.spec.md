---
status: APPROVED
approved_at: 2026-11-22
approved_by: "operadora, pregunta interactiva 2026-11-22"
priority: P2
developer_type: agent-single
created: 2026-11-22
author: Savia
phase: D
risk: L2
human_surface: false
related_specs: [SE-465, SE-443, SE-442, SPEC-SE-088-UA-ADOPT, SPEC-193, SE-505]
origin: "Estudio de un proyecto público de tutoría con agentes (DeepTutor, Apache-2.0; sin copiar código ni texto), pedido por la operadora el 2026-11-22. De seis lecciones candidatas, el contraste con main f58dd82ce dejó una sola con hueco real. Informe en Savia Labs."
timeline:
  - from: "2026-11-22"
    learned: "2026-11-22"
    value: "PROPOSED"
    source: "orquestadora; encargo de la operadora en el chat del 2026-11-22"
  - from: "2026-11-22"
    learned: "2026-11-22"
    value: "APPROVED"
    source: "operadora, pregunta interactiva; «Aprobarla (Recommended)»"
---
# SE-535 — Entrada de skills externas: retirar lo que no se usa; la puerta queda en reserva

## Problema (verificado en origin/main f58dd82ce, 2026-11-22; lectura estática)

Una skill es texto que un agente obedece. Savia tiene una regla contra el envenenamiento de instrucciones entre agentes y un saneado de escrituras en memoria (SPEC-193), pero la entrada de skills de terceros no pasa por ningún control.

1. **El único instalador real enlaza sin leer.** `scripts/ua-install.sh` clona un repositorio externo con `git clone --depth 1`, sin commit fijado; con `--force` hace `git pull`. Después recorre su carpeta `skills/` y enlaza cada directorio con `ln -sfn` en `~/.agents/skills`. Ningún paso abre un `SKILL.md`. Lo que el repositorio externo publique mañana queda instalado en la siguiente ejecución.
2. **Sus dependencias tampoco están fijadas.** `pnpm install --frozen-lockfile` cae a `pnpm install` si falla; lo mismo con `npm`. SE-465 lo tiene registrado como excepción con la decisión D1 sin tomar (`scripts/pinned-installs-exceptions.txt`, línea 9).
3. **Las órdenes de marketplace no tienen implementación.** `/marketplace-install`, `/marketplace-search` y `/marketplace-publish` son tres ficheros de instrucciones para el modelo. Citan `data/marketplace/registry.json`, que no existe, y ningún script. «Validar checksum (si disponible)» es una frase, no una comprobación.
4. **Una spec aprobada se apoya en ese hueco.** SE-443 S2 prevé invocar la comprobación de malware «desde `/marketplace-install`». Hoy no hay código donde colgarla.
5. **No hay registro de procedencia.** Ningún fichero dice qué skill externa está instalada, de qué commit ni desde cuándo.

**Lo que no se ha observado.** Ningún incidente. En la máquina de referencia la integración externa no está instalada (no existen `~/.opencode/understand-anything` ni `~/.agents/skills`); es una sola muestra y no hay dato de otras instalaciones.

## Decisiones de la operadora (2026-11-22, pregunta interactiva)

| # | Pregunta | Respuesta literal |
|---|---|---|
| D1 | Integración externa Understand-Anything: ¿qué hacemos con ella? | «Retirarlo (Recommended)» |
| D2 | Órdenes `marketplace-*` sin implementación: ¿qué hacemos? | «Retirarlas (Recommended)» |
| D3 | `scripts/memory-experiments.py`, sin más uso que su propio test: ¿qué hacemos? | «Retirarlo en SE-535 (Recommended)» |
| — | ¿Apruebas la spec? | «Aprobarla (Recommended)» |

D1 y D2 se respondieron en una primera pregunta; D3 y la aprobación, en una segunda el mismo día.

**Consecuencia.** Con D1 no queda ningún camino por el que entre una skill externa. Por la regla «conectar antes de construir», la puerta no se construye: una puerta sin nada que entre por ella es código sin consumidor. Esta spec pasa a ser de retirada; el diseño de la puerta se conserva en reserva al final.

## Qué decide esta spec

Retirar los dos caminos y un guion sin uso hallado en la misma revisión, en tres slices independientes, y dejar escrito con qué condiciones se reabriría una entrada de skills externas.

| Slice | Entrega | Tier |
|---|---|---|
| S1 | **Retirada de las órdenes de marketplace.** Se eliminan `.claude/commands/marketplace-{install,search,publish}.md` y sus referencias en `.claude/profiles/context-map.md`, `.claude/settings.json`, `.claude/commands/tenant-create.md`, `.claude/commands/tenant-share.md`, `scripts/test-multi-tenant.sh` y `vault/00-Index/Commands.md`. SE-443 S2 deja de citar `/marketplace-install` y se queda con sus otros dos puntos de invocación (`/mcp-recommend` y el alta de conectores de Space). | previsible 4 (toca `settings.json`); se calcula al implementar |
| S2 | **Retirada de la integración externa.** Se eliminan `scripts/ua-install.sh`, `scripts/ua-bridge.sh`, las siete órdenes `.claude/commands/ua-*.md`, la skill `.claude/skills/understand-anything/` y sus dos suites (`tests/test-understand-anything.bats`, `tests/test-spec-se-088-ua-adopt.bats`). Se limpian catálogos e índices (`SKILLS.md`, `docs/RESOLVER.md`, `skills-manifest.json`, `skills-registry/INDEX.json`, `vault/00-Index/`), la línea 9 de `scripts/pinned-installs-exceptions.txt` y la mención en SE-465 D1. `SPEC-SE-088-UA-ADOPT` pasa a RETIRED por su ciclo de vida, con esta spec como motivo. | previsible 3; se calcula al implementar |
| S3 | **Retirada del guion de experimentos de memoria.** Se eliminan `scripts/memory-experiments.py` y `tests/evals/test-memory-experiments.bats`, y su línea en `vault/00-Index/Scripts.md`. **No** se toca `tests/evals/memory-benchmark-store.jsonl`: lo usan `scripts/benchmark-context-pipeline.py` y otras tres suites. Ajeno a las skills externas; va aquí por decisión D3. | previsible 2; se calcula al implementar |

Cada slice va en su PR. Los recuentos de órdenes y skills que citan `CLAUDE.md` y los README se actualizan en la misma PR que los cambia.

**Condición de reapertura.** Cualquier propuesta futura de instalar skills de terceros (esta integración u otra) entra por la puerta en reserva; no se acepta un instalador que copie o enlace por su cuenta.

## Criterios de aceptación

| AC | Criterio | Slice | autoridad_requerida |
|---|---|---|---|
| AC-1 | Ningún fichero del repositorio referencia `marketplace-install`, `-search` ni `-publish`, salvo historial de cambios y specs cerradas | S1 | estatica |
| AC-2 | SE-443 no cita ninguna orden inexistente: cada punto de invocación de su S2 existe en el repositorio | S1 | estatica |
| AC-3 | **Negativo:** `scripts/test-multi-tenant.sh` pasa sin las tres órdenes y falla si alguna reaparece sin implementación | S1 | real |
| AC-4 | No existen `scripts/ua-install.sh`, `scripts/ua-bridge.sh`, las órdenes `ua-*` ni la skill; ningún catálogo, índice o manifiesto las lista | S2 | estatica |
| AC-5 | `scripts/pinned-installs-exceptions.txt` no contiene la excepción y el comprobador de SE-465 pasa sin ella | S2 | real |
| AC-6 | **Negativo:** ningún guion del repositorio contiene `ln -s` hacia un directorio de skills ni clona un repositorio de skills sin commit fijado; el comprobador lo detecta sobre un caso sembrado | S2 | real |
| AC-7 | Los recuentos de órdenes y skills declarados en la documentación coinciden con el árbol; la auditoría de deriva pasa | S1, S2 | real |
| AC-8 | Cada slice se revierte con una sola PR de reversión, sin pasos manuales | S1, S2, S3 | estatica |
| AC-9 | No existen `scripts/memory-experiments.py` ni su suite; ningún índice los lista | S3 | estatica |
| AC-10 | **Negativo:** las suites que usan `tests/evals/memory-benchmark-store.jsonl` siguen pasando y el fichero no cambia | S3 | real |

## Entregables de planificación (rutas)

La aprobación y el registro de esta spec tocan, además de este fichero: `docs/propuestas/planning.d/SE-535.json`, `docs/propuestas/LOG.d/SE-535-PROPOSED.md`, `docs/propuestas/LOG.d/SE-535-APPROVED.md` y la vista generada `docs/propuestas/ROADMAP-CURRENT.md` (salida de `scripts/roadmap.sh render`; no se edita a mano).

## Fuera de alcance

- Servidores MCP y conectores (SE-443), salvo corregir su punto de invocación.
- Fijado de dependencias de `npm` y `pip` (SE-465), salvo retirar la excepción.
- Plugins del frontend, que tienen su propio mecanismo de instalación.
- Construir la puerta.

## Riesgos

- **Alguien usa la integración y no lo sabemos.** Solo hay una máquina observada. La retirada es reversible (AC-8) y el diseño de la puerta queda listo para reintroducirla bien.
- **Referencias colgadas.** Los catálogos generados y los recuentos se rompen con facilidad al borrar órdenes; por eso AC-7.
- **S1 toca configuración sensible.** Modifica `settings.json`: revisión humana expresa de esa PR y fuera de cualquier lote de fusiones.

## Diseño en reserva: la puerta (no se construye)

Se conserva para la condición de reapertura. Un único guion, `scripts/skill-intake.sh`, con `check` (solo lectura) e `install`:

| Regla | Contenido |
|---|---|
| R1 Origen fijado | URL y commit completo (40 hexadecimales). Rama, etiqueta o `HEAD` se rechazan. |
| R2 Copia defensiva | Se copia, no se enlaza. Solo ficheros regulares dentro del directorio. Rechazo de la skill entera ante enlace simbólico, ruta que escape, más de 200 ficheros, más de 5 MB o binario ejecutable. Sin bits de ejecución. |
| R3 Cabecera reducida | Solo `name`, `description`, `license`, `compatibility` y `metadata`. El resto se retira, en particular lo que amplía alcance (`allowed-tools`, `hooks`, `model`, `always`), y consta en el recibo. |
| R4 Destino separado | Capa de usuario, fuera del repositorio. Nombre igual al de una skill propia: rechazo. |
| R5 Recibo | `~/.savia/skill-intake.lock.json`: nombre, URL, commit, hash del árbol, fecha, claves retiradas, veredicto y quién confirmó. Privado, sin versionar. |
| R6 Fallo en cerrado | Sin veredicto de escáner: `sin verificar` y confirmación expresa de la persona con la lista delante. No interactivo sin confirmación registrada: error. Un agente nunca confirma. |
| R7 Actualizar es volver a entrar | Otro commit invalida la confirmación anterior. Sin actualización en segundo plano. |
| R8 Sin red al arrancar | Solo por orden explícita. |

Límite conocido: retirar claves de la cabecera no neutraliza el cuerpo de la skill. La puerta reduce alcance y deja rastro; no certifica.

Si se reabre, la spec que la construya tiene superficie humana (una pregunta antes de instalar) y debe pasar la puerta de comprensión (SE-505) con escenas confirmadas y prototipo; además es pieza de autoridad y lleva TDD cruzado. Escenas de partida, **sin confirmar**: (1) al instalar, Savia enseña origen, commit, ficheros y claves retiradas y pregunta; (2) una skill con enlace simbólico se rechaza con su motivo; (3) el repositorio externo cambia y en tu máquina no cambia nada; (4) un agente de noche no puede instalar.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Órdenes retiradas | `.claude/commands/marketplace-*.md`, `.claude/commands/ua-*.md` | Las mismas, vía el enlace `.opencode/commands` |
| Skill retirada | `.claude/skills/understand-anything/` | La misma, vía el enlace `.opencode/skills` |
| Configuración | `.claude/settings.json` (entrada de `marketplace-search`) | Sin entrada equivalente |

### Verification protocol

- [ ] Ninguna orden retirada aparece en el listado de órdenes de ninguno de los dos frontends
- [ ] Las suites de catálogo y deriva pasan en ambos
- [ ] No se registra ni se elimina ningún hook

### Portability classification

- [x] **PURE_BASH**: retirada de ficheros comunes; ningún binding específico de frontend.

## Aprobación

**Aprobada por la operadora el 2026-11-22** por pregunta interactiva («Aprobarla (Recommended)»), con las decisiones D1 a D3 de la tabla. Sin superficie humana en lo que se construye, no requiere escenas. Cada slice se fusiona con la revisión de su PR concreta. Se formaliza al fusionar esta PR (SE-488).
