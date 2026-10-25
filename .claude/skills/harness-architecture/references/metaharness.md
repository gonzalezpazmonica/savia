# Metaharness: harness que lanza harnesses — EXPERIMENTAL

**Estado: línea de investigación abierta (L39), sin confirmar.** No es una recomendación general.
Esta referencia describe la idea para decidir con criterio, no para adoptarla.

## Evidencia disponible [E]

- Un caso real de delegación en un harness hijo con autoridad de la persona.
- Ventaja medida de un ejecutor por contratos sobre código con tests ocultos: +3-4 puntos, 19 tareas emparejadas, 2-3 repeticiones, sin significación formal.
- Desventaja medida en investigación web: el hijo citó fuentes sin abrirlas.
- Ninguno gana en todo. No hay evidencia independiente de que enrutar entre harnesses supere al mejor harness único. Hay hipótesis abiertas sobre el sobrecoste.
- Contexto externo: el mismo modelo en 8 harnesses dio del 68 % al 88 % en 25 tareas (un solo modelo, una ejecución por tarea, estudio de un proveedor de herramientas) [M: C6]. Dice que el harness importa, no que una capa extra compense.

## Cuándo se justifica

Solo si se cumplen **todas**: hay al menos dos harnesses con ventajas medidas en dominios distintos; la autoridad debe venir de una persona; y se va a medir el sobrecoste. Con un solo harness, tarea corta, o sin medir coste y calidad, no lo uses.

## Reglas

1. Cada hijo tiene una **ficha** (`plantillas.md`, A): capacidades, gobierno, invocación, coste medido, evidencia, puntos fuertes y débiles. Sin medida: `null`.
2. Gobierno válido: `contrato`, `solo-lectura` o `propio`. Nunca un modo sin permisos.
3. **Invocación determinista**: proceso headless con herramientas explícitas y timeout. Los procesos `claude -p` terminaron todos; los subagentes interactivos en segundo plano se colgaron esperando un permiso que nadie veía. [E] En el SDK los subagentes corren en segundo plano por defecto y heredan el modo de permisos del padre [D: A9]: preconcede los permisos.
4. El resultado se acepta solo si pasa la **postcondición** en el directorio de trabajo, no por lo que el hijo diga.
5. La madre aporta lo que la hija no tiene (p. ej. revisión) sin ampliarle la autoridad. [E]
6. Enruta con reglas simples por tipo de tarea antes de pensar en un enrutador aprendido. [O; hipótesis abierta]
7. Mide el sobrecoste (arranque del hijo + traspaso) frente a hacerlo en línea. Umbral de trabajo de la línea de investigación: si supera el 30 % del total, la capa no compensa. No es una cifra externa. [E]
8. Arranque de un hijo en Claude Code: unos 22-26k tokens medidos. [E]
9. Una evaluación comparativa da a todos las **mismas herramientas** que tendrían en uso real. Una ronda sesgada por permisos dio 7,0 frente a 1,5; en igualdad, 6,83 frente a 6,17. [E]

## Para pasar de experimental a recomendado

Comparación con herramientas iguales sobre tareas reales, varias repeticiones, sobrecoste medido y al menos un caso donde la capa gane al mejor harness único tras restar su coste. Si L39 se cierra en negativo, se poda esta referencia.

## Diseño automático de harnesses (ADAS, harness2)

Solo offline y con batería de evaluación. La mejora de harness2 es autodeclarada y cuesta unas 4k ejecuciones por tarea [O: G1]. La puerta y la política nunca son editables por el agente: como mucho propone enmiendas que aprueba la persona. [E]
