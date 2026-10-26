# Catálogo de patrones de orquestación

Orden de preferencia: de arriba abajo. No pases al siguiente patrón sin un fallo observado del anterior.
Etiquetas de evidencia: ver `SKILL.md`. Fuentes por clave en `fuentes.md`.

| # | Patrón | Úsalo cuando | Coste | Riesgo principal | Origen |
|---|---|---|---|---|---|
| 1 | Una llamada o prompt | La tarea cabe en un paso | mínimo | Ninguno | A1 |
| 2 | Agente único con herramientas | Tarea abierta que cabe en un contexto | bajo | Desbordar contexto | A1, OA1, C1 |
| 3 | Flujo fijo (encadenado, enrutado, paralelo, evaluador-optimizador) | Los pasos se conocen de antemano | bajo-medio | Rigidez | A1, G2 |
| 4 | Agente + subagentes de consulta | Lectura o investigación voluminosa; vuelve un resumen | medio | Resumen que pierde detalle | A4, C1 |
| 5 | Orquestadora + trabajadoras en paralelo | Subtareas independientes, amplitud, ficheros disjuntos | alto (≈15x tokens de un chat en investigación [M-int]) | Decisiones en conflicto | A6; C1 lo desaconseja con decisiones acopladas |
| 6 | Productor + verificador | Hay que fiarse de un resultado | medio | Mismo sesgo si es el mismo modelo | A3, A10 [O]; SE-228/SE-433 [E] |
| 7 | Inicializadora + sesiones incrementales | El proyecto supera una ventana de contexto | medio | Estado en ficheros mal mantenido | A2 |
| 8 | Bucle con criterio externo (estilo Ralph) | Backlog grande de tareas mecánicas con test | alto sin tope | Bucle infinito, trabajo de relleno | C2 |
| 9 | Metaharness (**experimental**) | Ver `metaharness.md` | alto | Capa extra sin ganancia demostrada | L39, propuesta |
| 10 | Meta-agente que diseña harnesses (ADAS, harness2) | Solo offline y con batería de evaluación | muy alto (4k ejecuciones por tarea, autodeclarado) | Autoedición sin gobierno | G1, C5 |

## Reglas de elección

1. Subtareas con decisiones compartidas (estilo, interfaces, esquema): un solo hilo. Independientes y de lectura: paralelo. [O: A6 y C1 se concilian así]
2. Paralelo de escritura solo con ámbitos de ficheros disjuntos, verificados antes de lanzar. [E]
3. Un hijo recibe un encargo autocontenido: objetivo, formato de salida, herramientas, límites, criterio de éxito. Un subagente del SDK parte de una conversación vacía y solo su último mensaje vuelve al padre. [D: A9; O: A6]
4. Hijo de trabajo largo: invocación determinista (`claude -p` con herramientas explícitas y timeout), no subagente interactivo. [E]
5. El hijo escribe un artefacto y devuelve la ruta más 1-3 líneas. [O, E]
6. Un hijo no recibe más autoridad que la que la persona le dio. El SDK ya lo hace así con el modo de permisos: un subagente corre en `bypassPermissions` solo si lo hace el padre. [D: A9]
7. Anidar subagentes es posible (profundidad 3 por defecto en el SDK, configurable) pero cada nivel multiplica coste y pérdida de contexto: no lo uses sin un fallo observado. [D: A9; O]

## Condiciones de salida de un bucle (al menos dos, y una externa al agente)

- Criterio de éxito comprobable (test verde, esquema válido).
- Máximo de iteraciones o de turnos (`maxTurns` en el SDK; sin límite por defecto). [D: A9]
- Máximo de reintentos consecutivos por unidad.
- Detector de repetición (misma acción N veces).
- Presupuesto de tiempo o dinero (`maxBudgetUsd` en el SDK; puede excederse en el coste de una respuesta). [D: A9]
- Fichero de parada o revocación.
