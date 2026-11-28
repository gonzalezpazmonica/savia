---
status: APPROVED
approved_at: 2026-10-05
approved_by: "operadora, AskUserQuestion 2026-10-05"
priority: P1
developer_type: agent-single
created: 2026-10-03
author: Savia
phase: A
risk: L2
related_specs: [SE-428, SE-429, SE-430, SE-431]
origin: "Mandato de la operadora (2026-10-02): escritorio infinito con objetos, conexiones, cúpulas y flujos renderizados en tiempo real; la experiencia UX es el punto más diferenciador de Savia; gestión de temas sin imponer estética. Decisiones (AskUserQuestion): render híbrido WebGL+DOM, escritorio en 0.2, tablero Universo y tableros por proyecto, prototipo con aceptación visual"
resource: https://pixijs.com/
---

# SE-432 — Savia Space: escritorio infinito y experiencia

## Problema

SE-428 define a Savia Space como sustituto de OpenCode, pero no describe su superficie principal.
Una TUI, o una web con listas, no deja ver lo que hace un sistema de muchos agentes:

- qué sesiones corren y qué esperan de la operadora;
- qué cúpulas se citan;
- qué flujos atraviesan proyectos;
- qué hooks actuaron.

El encargo es un **plano infinito** donde todo eso se ve en tiempo real. La experiencia tiene que
ser impresionante y, a la vez, dar paz y control. Las primeras capturas de un prototipo oscuro de
puntos y líneas se percibieron como básicas: la estética no se impone, la gestiona la persona.

## Objetivo

Que la operadora entienda el estado de todo su trabajo de un vistazo, y que pueda acercarse
a cualquier objeto y actuar sobre él sin cambiar de herramienta.

- **Ontología propia**: objetos tipados (proyectos, sesiones, runs, agentes, skills, comandos,
  cúpulas, notas, ramas, PRs, checks, permisos, hooks) y enlaces con soporte visible:
  - observado: línea continua;
  - declarado: discontinua;
  - inferido: punteada.
  El patrón es el de Ontology/Object Explorer de Palantir, con un diseño propio.
- **Zoom semántico**: Universo → galaxia de proyecto → sesión → detalle. Cada nivel muestra lo que
  se puede leer a esa distancia: haces de enlaces, etiquetas y tarjetas.
- **Tiempo real honesto**: un pulso, un flujo o un destello solo aparece con un evento real.
  La luz de una región sale de su estado real (runs en marcha, permisos esperando). Lo ambiental
  nunca imita actividad.
- **Mover, hacer zoom o seleccionar nunca cambia contexto, manifest ni permisos.** Un enlace
  dibujado no concede nada.

## Diseño

### Render

- **Híbrido**:
  - WebGL (PixiJS 8, MIT) para objetos, enlaces, regiones y flujos;
  - DOM para las tarjetas cercanas, el inspector, el chat y la paleta;
  - una **lista accesible paralela**, con el mismo recorrido completo por teclado.
- **Escala**:
  - rejilla espacial para culling;
  - LOD por tamaño en pantalla;
  - haces de enlaces a distancia;
  - pool de tarjetas DOM (≈36) que evitan los paneles abiertos.
- **Cámara** con muelles críticamente amortiguados:
  - el zoom con rueda mantiene fijo el punto bajo el cursor;
  - la inercia es interrumpible;
  - «seguir» se detiene con cualquier gesto manual.
- **Pipeline**: SSE → reducer por secuencia → diff de escena por lote en `requestAnimationFrame` → GPU.

### Apariencia gestionada por la persona

- **Modo**: sistema (por defecto), claro u oscuro. Nunca oscuro impuesto.
- **Paleta y acento**:
  - paletas cálida, neutra y fría;
  - acento libre;
  - colores derivados en OKLCH para que cualquier acento quede armónico.
- **Contraste** comprobado con WCAG: AA, y AAA con alto contraste.
- **Densidad, movimiento** (sistema, completo o reducido) y **efectos** (auto según la GPU, alta,
  media o baja).
- Preferencias locales por dispositivo, validadas al cargar.

### Atmósfera y señal

- **Atmósfera** (nunca cuenta nada):
  - estrellas con paralaje;
  - nebulosas por región;
  - grano;
  - esferas iluminadas con sombra de contacto;
  - tarjetas de cristal con desenfoque.
- **Señal** (siempre real):
  - estelas de flujo entre objetos;
  - destellos de check o permiso;
  - pulso de la tarjeta afectada;
  - cursores de agente sobre citas;
  - envolvente de la sesión en marcha.
- **Calma**: un fallo es «ruidoso» solo durante 90 s; después queda como estado, sin alarma.

### Interacción

- Paleta ⌘K, inspector con acciones por tipo, modo foco y minimapa.
- Chat flotante que cita como chips los objetos seleccionados. Solo envía referencias, nunca una
  captura; el texto entra solo tras selección y preview.
- Toda acción con efecto pasa por el motor y los hooks de SE-428. El plano no tiene un camino propio.

## Fuera de alcance

- Paneles y vistas compartidas (0.4); capa de control de Soul (0.5, SE-431).
- Voz sobre «lo que ves».
- Edición colaborativa del tablero.

## Entregas

- **0.2**: escritorio como superficie principal de SE-428, con:
  - capas de trabajo, assets y ejecución;
  - tablero por proyecto;
  - apariencia completa;
  - lista accesible.
- **0.3**: tablero Universo, capa de conocimiento (cúpulas y citas), linaje y modo REPLAY.
- **0.4**: escritorio simplificado en el móvil (SE-430).

## Criterios de aceptación

- **AC1**: con 10 000 objetos y 50 eventos/s en Chrome con GPU discreta, en el banco reproducible
  `e2e/desktop.bench.mjs`:
  - frame p95 ≤ 16,7 ms en pan del Universo, zoom y pan cercano;
  - evento→pintado p95 ≤ 100 ms;
  - cero errores de consola.
- **AC2**: sin preferencias guardadas, el modo sigue al del sistema, y cambia si el sistema cambia.
- **AC3**: con cualquier acento de la paleta o uno libre, el contraste de texto sobre panel es
  ≥ 4,5:1, y ≥ 7:1 con alto contraste.
- **AC4**: sin eventos durante 60 s, ningún objeto pulsa ni emite flujo; la luz de una región solo
  varía si cambia su estado.
- **AC5**: con movimiento reducido, no hay animaciones ni transiciones, y la información es la misma.
- **AC6**: mover, hacer zoom o seleccionar no genera llamadas al motor y no cambia el manifest.
- **AC7**: solo con teclado se completa el recorrido: buscar, ir, inspeccionar, aprobar un permiso
  y volver.
- **AC8**: una cúpula sin permiso no aparece: ni su nodo, ni su cuenta, ni sus enlaces.
- **AC9**: la operadora acepta visualmente el prototipo en claro y en oscuro antes de cerrar 0.2.
  Si lo rechaza, el motivo se registra.

## Decisiones pendientes

- **D1**: familia tipográfica e iconos con licencia libre.
- **D2**: avatar de Savia (buhita) en el producto. **Decidida el 2026-11-26** por la operadora en pregunta interactiva («Sí, la misma (Recommended)»): Space y Sonora comparten la misma cara, con el formato de estilos de SE-538.
- **D3**: dirección visual por defecto tras la prueba de la operadora.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode |
|---|---|---|
| Escritorio (web) | no aplica | no aplica: cliente propio de Space; consume eventos del motor vía el adaptador de SE-428 |
| Acciones desde el plano | hooks de Savia vía el bus de Space (SE-428) | permisos y prompts al motor `opencode serve` |

### Verification protocol

- [ ] Tests unitarios de cámara, rejilla espacial, LOD, tarjetas, apariencia y atmósfera.
- [ ] Banco en navegador real (AC1) y capturas en claro y oscuro como regresión visual.
- [ ] AC4–AC8 como escenarios e2e; AC9 con la operadora.

### Portability classification

- [x] **DUAL_BINDING**: el escritorio es cliente propio de Space; toda acción con efecto pasa por el
  bus de hooks (contrato de Claude Code) y por el motor OpenCode con su plugin de guards, como en SE-428.
