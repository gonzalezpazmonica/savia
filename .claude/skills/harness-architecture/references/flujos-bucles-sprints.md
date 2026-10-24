# Flujos largos, bucles y sprints nocturnos

Etiquetas de evidencia en `SKILL.md`. Fuentes por clave en `fuentes.md`.

## 1. Flujos largos

Patrón [O: A2]:

1. **Inicializar**: entorno reproducible, lista de tareas (todas «pendientes»), fichero de progreso, commit inicial.
2. **Avanzar**: una unidad por sesión; al cerrar, estado limpio, commit y progreso actualizado.
3. **Reanudar** (tras compactación, límite de uso o noche): leer progreso, historial git y lista; ejecutar la comprobación básica; continuar con una sola unidad.
4. Tras un hueco: lista de agentes vivos + marcas de fin + estado git de cada rama. [E]

Reglas:

- Solo se cambia el campo de estado de la lista, nunca su definición. [O: A2]
- El checkpoint registra la huella de configuración; se rechaza reanudar con otra política. [O: G1]
- Lo que debe sobrevivir a una compactación vive en ficheros. En el SDK, la compactación resume el historial antiguo y las instrucciones tempranas pueden perderse; hay evento `PreCompact` y CLAUDE.md se reinyecta en cada petición. [D: A9]
- Sesiones: el SDK reanuda por id y bifurca una sesión; persiste la conversación, no el sistema de ficheros. [D: A9]
- Pruebas de extremo a extremo cuando se pueda. [O: A2]
- No supongas que algo no existe por una sola búsqueda. [O: C2]
- Los traspasos llevan referencias a artefactos, no solo un resumen. [O, E] Cada traspaso cuesta: mide cuántos necesita el flujo. (La cifra «más de cuatro traspasos casi siempre fallan» no pudo verificarse en su fuente: solo como pista.)

## 2. Bucles

Un bucle sin parada es gasto sin límite. Define **antes de lanzar**:

| Elemento | Regla | Respaldo |
|---|---|---|
| Criterio de éxito | Ejecutable por máquina | O |
| Unidad | Un ítem por vuelta | O: C2 |
| Máximo de iteraciones | Un número, no «hasta que acabe» | O: G2, OA1; D: A9 |
| Reintentos por unidad | Tres fallos seguidos y se aparca | E; OA1: el umbral de fallos escala a persona |
| Detector de repetición | La misma acción tres veces: bloquear | E |
| Presupuesto | Tiempo, tokens y dinero con tope | M-int: A6; E |
| Parada externa | Fichero de parada o revocación | E |
| Registro | Una línea por intento: resultado, coste, causa | E |

Reglas:

1. Sin criterio de éxito comprobable no hay bucle: es un informe (nivel L1). [E]
2. Prohíbe soluciones de relleno en el encargo y comprueba con tests por unidad. [O: C2]
3. Dos intentos para una propuesta inválida y vuelta a lo conocido, sin tercer intento. [O: G1]
4. Si una instrucción se ignora repetidamente, súbela de nivel: prosa, script, hook. [O: G1; `remedy-ladder.md`]
5. Cambia de estrategia tras el segundo fallo igual; no repitas el mismo intento. [O] Los umbrales no se contradicen: dos intentos valen para una propuesta nueva (paso 3), el mismo fallo exige cambiar de estrategia al segundo (paso 5) y tres fallos seguidos de una unidad la aparcan y escalan (tabla de bucles).
6. Escala a la persona por umbral de fallos y por acción de alto riesgo o irreversible. [O: OA1]

## 3. Sprints nocturnos

Todo sale de fallos reales de Savia [E] salvo indicación.

1. **Cola explícita**: plan de sprint (`plantillas.md`, C) con unidades, ámbito de ficheros, dependencias y éxito verificable.
2. **Permisos preconcedidos** para todo lo que el sprint necesita. Un diálogo de permiso nadie lo ve de noche.
3. **No bloquear con preguntas**: antes de preguntar, deja todo despachado y los vigilantes rearmados; las decisiones no urgentes se acumulan y se preguntan en lote.
4. **Vigilantes con lista de vistos**, no con recuento: el recuento pierde entregas simultáneas.
5. **Marca de fin obligatoria** en cada encargo, aunque falle. En cada despertar, compara agentes esperados con los vivos: hay agentes que terminan sin marca.
6. **Un PR por unidad**, en borrador, en rama propia del agente. Revisor independiente en el mismo turno de abrirlo.
7. **Merges solo con grant** expreso y vigente sobre una lista concreta. El ejecutor de merges es determinista; ningún LLM decide un merge. Ver `autonomous-safety-merge-sprint.md`.
8. **Presupuesto de recursos**: agentes simultáneos, disco, RAM, tmpfs. Comprueba el disco en cada ciclo; las compilaciones van a disco, no al scratchpad en tmpfs.
9. **Paralelismo = política, no ley técnica.** El tope de agentes simultáneos lo marcan dos límites ajenos al diseño: la **cuenta** (consumo de tokens y cuota) y la **máquina** (RAM, disco, CPU). Anota en el plan el valor y quién lo fijó. Mantén la cola llena hasta ese tope; una orden expresa de la persona puede moverlo. El SDK trae su propio tope por defecto (20 subagentes simultáneos) y es configurable: es un ajuste del producto, no una recomendación [D: A9].
10. **Parar es seguro**: un sprint detenido por una condición de parada no se reanuda sin grant nuevo.
11. **Informe final**: qué se hizo, qué falló, coste (real frente a declarado), qué queda.
