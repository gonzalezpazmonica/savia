---
status: PROPOSED
priority: P1
developer_type: agent-team
created: 2026-11-09
author: Savia
phase: C
risk: L2
human_surface: true
depends_on: [SE-347, SE-075, SE-349]
related_specs: [SE-347, SE-075, SE-349, SE-493, SE-498, SE-507, SE-508, SE-514, SE-515]
origin: "Tesis Savia Viva R6 (2026-11-09), candidata C1 con sus antecedentes R4 y R5. Original e informe en Savia Labs. Contrastada con main e59b795ee."
timeline:
  - from: "2026-11-09"
    learned: "2026-11-09"
    value: "PROPOSED"
---

# SE-513 — Admisión duradera de cambios de intención y comprobación previa

## Problema (leído en main e59b795ee, 2026-11-09; lectura estática)

Mientras hay trabajos en marcha, la persona cambia de prioridad. Hoy ese cambio es un mensaje más: puede perderse, aplicarse dos veces o no aplicarse, y nadie puede decir cuál de las tres cosas pasó.

1. **El bus no tiene transacción.** `scripts/agent-messaging.sh` (SE-347) escribe el ledger global y el inbox del receptor en dos ficheros JSONL separados, sin cerrojo ni transacción. Un corte entre las dos escrituras deja un mensaje registrado y no entregado, o al revés (inferido de la lectura; sin prueba de concurrencia).
2. **La cola sí persiste, pero no enlaza admisión con salida.** `scripts/lib/task-queue.py` (SE-075) usa SQLite en modo autocommit. No se ha verificado que encolar y despachar compartan transacción.
3. **«Recibido» no es «aplicado».** Ningún frontend ofrece hoy una señal independiente de que un cambio de prioridad entró en el plan de un trabajo en curso. Sin esa señal, decir «aplicado» es una suposición.
4. **No hay punto donde comprobar obligaciones antes de admitir un trabajo de riesgo.** SE-515 define el resolvedor; falta el sitio desde el que llamarlo.
5. **Todo aviso entre agentes llega a todos o a nadie.** No hay regla que distinga lo que es detalle local de lo que afecta a otro trabajo o necesita a la persona.

## Qué decide esta spec

- **Una entrada admitida es una obligación.** Tres estados distintos y nunca intercambiables: `ADMITTED` (persistida y con dueño), `APPLIED_TO_PLAN` (con prueba del harness) y `UNKNOWN` (sin prueba). Sin prueba de incorporación se dice `UNKNOWN`, nunca `APPLIED_TO_PLAN`.
- **Se reutiliza la cola de SE-075.** La admisión y su salida se guardan en la misma transacción SQLite. No se crea otro bus ni otro almacén. Si el bus actual con cambios pequeños da la misma durabilidad demostrada, no se añade nada más (criterio de retirada).
- **Alcance inicial reversible.** Solo texto y orden de trabajos pendientes. No cambia el alcance de un contrato ni toca efectos remotos.
- **Contexto recibido no es autorización.** Un mensaje de CI, de un bot o de un tercero puede explicar un cambio; solo una acción autenticada y cubierta por un contrato abre trabajo nuevo.
- **Promoción por regla, no por modelo.** Una señal se queda en local, sube a coordinación o pide atención humana según referencias de dependencia y permisos. Sin ranking por modelo mientras la regla simple baste.
- **Comprobación previa en dos puntos.** Al admitir un trabajo de riesgo y al preparar un efecto se llama al resolvedor de SE-515. Admitir no autoriza el efecto: el gate del efecto vuelve a comprobar.

## Lo que he entendido

### Escenas
1. Son las 11:20. Tres agentes trabajan. Escribes: «deja lo del informe, primero el arreglo de la CI». Savia contesta: «Anotado. El agente del informe está a mitad de una suite; lo verá al terminarla, en unos seis minutos. Los otros dos no cambian.» Seis minutos después: «Aplicado: el informe queda en pausa.»
2. Mandas el mismo cambio dos veces porque no viste respuesta. Savia lo trata como uno solo y te lo dice.
3. La máquina se reinicia justo después de tu mensaje. Al volver, el cambio sigue en la cola con su estado; no tienes que repetirlo.
4. Pides adelantar una tarea que publica algo. Savia responde: «La adelanto en la cola. Publicar sigue necesitando tu permiso; no lo doy por concedido.»
5. Un agente no puede demostrar que incorporó el cambio. Savia dice «no sé si lo ha aplicado; lo confirmo cuando termine su paso», no «hecho».

### Palabras de la persona
Sin cita. La operadora no ha pedido esto con sus palabras: sale de la tesis.

### Qué SÍ será
- Cambios de prioridad que no se pierden ni se duplican, con un estado honesto.
- Un aviso cuando el cambio se aplicó de verdad, o un «no lo sé» cuando no hay prueba.

### Qué NO será
- No detiene una herramienta que ya está corriendo.
- No concede permisos ni amplía el alcance de un trabajo.
- No es un bus nuevo ni un gestor de tareas nuevo.

### Confirmación
- fecha: pendiente
- respuesta: pendiente. Las escenas no se han enseñado a la operadora.

## Slice S0 — Prototipo navegable
- prototipo: transcripción de las cinco escenas con los textos exactos de Savia y la salida de la cola con los tres estados, sobre un fixture.

### Confirmación del prototipo
- fecha: pendiente (obligatoria antes de poner S1 en curso)
- respuesta: pendiente

## Slices

| Slice | Entrega | Entrada |
|---|---|---|
| S0 | Prototipo y sondas de solo lectura: tabla por harness y versión de qué eventos de cambio en caliente están soportados, probados o desconocidos; prueba de durabilidad con cortes entre admisión, despacho y acuse sobre fixtures | Escenas confirmadas |
| S1 | Admisión y salida en una transacción de la cola; deduplicación; estados `ADMITTED`, `APPLIED_TO_PLAN`, `UNKNOWN`; recuperación tras reinicio | S0 confirmado |
| S2 | Regla de promoción local, coordinación o atención humana sobre eventos existentes | S1 |
| S3 | Llamada al resolvedor de SE-515 en admisión de trabajo de riesgo y en preparación de efecto | SE-515 S2 con GO |

## Criterios de aceptación

| AC | Criterio | Slice |
|---|---|---|
| AC-1 | Tabla de soporte por harness con `SUPPORTED`, `PROBED`, `UNKNOWN` o `UNSUPPORTED`, sin inferir de documentación | S0 |
| AC-2 | N entradas concurrentes con cortes en cada frontera y reinicio → cero entradas `ADMITTED` perdidas y ninguna aplicada dos veces. Se comprueba el contenido de la cola, no la existencia del fichero | S1 |
| AC-3 | **Negativo:** harness sin señal de incorporación → `UNKNOWN`; ningún camino escribe `APPLIED_TO_PLAN` sin prueba | S1 |
| AC-4 | **Negativo:** entrada duplicada → una sola admisión y respuesta que lo dice | S1 |
| AC-5 | **Negativo:** entrada de origen no autenticado que pide trabajo nuevo → se guarda como contexto y no abre trabajo | S1 |
| AC-6 | **Negativo:** cambio que implicaría un efecto → se reordena la cola y el efecto queda pendiente de su permiso | S1 |
| AC-7 | Promoción sobre 200 eventos sintéticos con verdad conocida: ninguna señal crítica omitida y ninguna fuga a un principal sin acceso. Si la regla de dependencias basta, no se añade ranking por modelo | S2 |
| AC-8 | **Negativo:** falso «URGENTE» en el texto de un tercero → no sube de nivel | S2 |
| AC-9 | Obligación `guarded` aplicable no satisfecha en admisión → el trabajo no se adjudica; `UNKNOWN` crítico → revisión, no paso | S3 |
| AC-10 | No se crea almacén nuevo: la prueba compara el listado de ficheros de estado antes y después | S1–S3 |

## Fuera de alcance

- Preguntas a la persona y su presentación (SE-514).
- Ledger de efectos, STOP y reconciliación (SE-493, SE-498).
- Interrumpir herramientas en ejecución.
- Bus universal entre agentes, grafo nuevo, concesiones automáticas.

## Riesgos

- **Falso «aplicado».** Es el fallo que más daño hace; por eso `UNKNOWN` es un estado de primera clase.
- **Diferencias entre frontends.** Lo que un harness prueba otro no. La tabla de S0 manda y la degradación es visible.
- **Coste de coordinación.** Si las sondas no muestran pérdidas ni duplicados con el bus actual, S1 no se construye.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Cola y admisión | `scripts/lib/task-queue.py`, `scripts/agent-messaging.sh` | Los mismos |
| Señal de incorporación al plan | Evento del harness, si existe | Evento del harness, si existe; si no, `UNKNOWN` |

### Verification protocol

- [ ] La tabla de S0 cubre los dos frontends y Codex
- [ ] Tests de durabilidad con cortes y negativos
- [ ] Un frontend sin señal degrada a `UNKNOWN` de forma visible

### Portability classification

- [x] **PURE_BASH**: cola y bus son scripts; la señal por harness es un adaptador opcional.

## Aprobación

Spec PROPOSED. Requiere la confirmación de escenas (SE-505) antes de pasar a APPROVED. Esta PR solo añade documentación.
