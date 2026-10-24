# Anti-patrones y coste observado

Observaciones propias de Savia [E] salvo indicación: son incidentes reales, no estudios controlados.
Ninguna fuente externa mide la mayoría; es lo más original de esta skill.

| Anti-patrón | Coste observado | Remedio |
|---|---|---|
| Subagente interactivo en segundo plano que pide un permiso | Más de 6 h parado | Proceso headless con herramientas explícitas, o permisos preconcedidos |
| Pregunta bloqueante en mitad de un ciclo | 7 entregas sin procesar durante 4 h | Despachar y rearmar vigilantes antes de preguntar; preguntas en lote |
| Vigilante por recuento | Entregas perdidas durante ~1 h | Lista de vistos |
| Agente que termina sin marca de fin | ~40 min con 0 agentes | Marca obligatoria + comparar esperados con vivos |
| Orquestadora con ~400k tokens de contexto | 64 % del consumo semanal en 4 días [M-int] | Umbral de traspaso y sesión nueva |
| Agentes en paralelo sin presupuesto de disco | Disco al 100 %; «Disk quota exceeded» que parecía flaky | Presupuesto de disco/RAM; compilar en disco |
| Cola de PR sin revisor asignado | 33 PR acumulados en un día | Revisor al abrir el PR |
| Cambiar instrucciones de un agente en marcha por mensaje | Dos agentes bloqueados por el clasificador | Relanzar con encargo limpio |
| Evaluar con herramientas desiguales | 7,0 frente a 1,5 que solo medía acceso | Mismas herramientas para todos |
| Agente que cita fuentes sin abrirlas | Atribuciones que la página no contiene | Verificar la cita contra la fuente |
| Paralelo de escritura con ficheros solapados | Merge limpio y comportamiento incorrecto [E, O: C1] | Ámbitos disjuntos comprobados antes |
| Estructura heredada que el modelo nuevo ya no necesita | Coste y complejidad sin ganancia [O: A3] | Ablación al cambiar de modelo |
| Bucle sin tope | Gasto sin límite [O] | Condiciones de salida (`catalogo-patrones.md`) |
| Subir un nivel de orquestación sin fallo observado | Más de 20x de coste, mejora solo cualitativa [M-int: A3, una ejecución] | Decision Checklist, punto 2 |
| Guardarraíl cuyo fallo se lee como aceptación | Un control que falla abierto | Excepción = resultado desconocido, falla cerrado [D: OA2; `checker-fail-closed.md`] |
| Dato sensible en el mensaje de bloqueo | Se persiste y se reproduce [D: OA2] | Mensajes de bloqueo sin valores |
