# Checklist de diseño de un harness

Úsala antes de lanzar un harness o al revisar uno existente. Cada punto indica su respaldo (etiquetas en `SKILL.md`; fuentes por clave en `fuentes.md`).

## 1. Contrato y autoridad
- [ ] Propósito de una frase, efectos permitidos y prohibidos. [O]
- [ ] La autoridad viene de la persona (contrato o grant), no de la orquestadora. Delegar nunca amplía. [E]
- [ ] Lo que hace cumplir el contrato es código fuera del modelo (hook, sandbox, permisos), no prosa. [O: B1, OA1; E] Ver `remedy-ladder.md`.
- [ ] Condición de parada y caducidad (tiempo, turnos, dinero). Parar es inmediato y siempre permitido.
- [ ] Un hook que permite no salta las reglas de denegación: en el SDK el orden es hooks, deny, ask, modo, allow. [D: A9] Diseña las denegaciones como suelo.

## 2. Herramientas
- [ ] Pocas, sin solapes, nombres y parámetros inequívocos. OpenAI: importa el solape más que el número. [O: OA1; M-int: A7, −40 % de tiempo al reescribir descripciones]
- [ ] Respuestas acotadas; errores que dicen qué hacer. [O: A7]
- [ ] Riesgo por herramienta (lectura o escritura, reversible, permisos, impacto económico) y acción automática según riesgo: pausa, comprobación o escalado a persona. [O: OA1]
- [ ] Ninguna herramienta pide entrada interactiva; los permisos que necesita el trabajo están preconcedidos o el harness se cuelga. [E]

## 3. Guías y sensores
- [ ] Hay guías (antes de actuar) **y** sensores (después). Solo sensores: repite errores; solo guías: nunca sabe si funcionaron. [O: B1]
- [ ] Controles baratos y deterministas (tests, linters, tipos) en cada cambio; los inferenciales (revisión por modelo) más caros y después. [O: B1]
- [ ] La salida de un sensor está escrita para el agente: qué falló y cómo corregirlo. [O: B1]
- [ ] Cada vez que un fallo se repite, se mejora la guía o el sensor, no solo el caso. [O: B1]

## 4. Contexto y compactación
- [ ] Arranque mínimo; lo demás, bajo demanda. [O: A4]
- [ ] Lo que debe sobrevivir a la compactación vive en ficheros: el SDK avisa de que instrucciones tempranas de la conversación pueden perderse y recomienda CLAUDE.md, que se reinyecta en cada petición. [D: A9]
- [ ] Umbral de traspaso y fichero de traspaso. [E]
- [ ] Subagentes devuelven resumen corto (1-3 líneas + ruta). [O: A4; E]

## 5. Memoria y traspaso
- [ ] Estado en ficheros: lista de tareas con estado, registro de progreso, historial git. [O: A2]
- [ ] Solo se cambia el campo de estado de la lista, no su definición. [O: A2]
- [ ] Reanudar = recuperar sesión por id o bifurcarla; el SDK persiste la conversación, no el sistema de ficheros, así que el estado de ficheros va aparte. [D: A9]
- [ ] Cada lección guardada: cue, lección, evidencia, confianza. [O: G1]

## 6. Verificación
- [ ] Criterio de éxito ejecutable por máquina. [O: A8, B1; M: M1]
- [ ] Se comprueba el artefacto, no el código de salida. [O]
- [ ] Verificador distinto del productor, contexto limpio, rechazo por defecto. [O: A3]
- [ ] Veredicto en formato fijo; la primera línea manda; cualquier otra forma cuenta como rechazo. [E] Una excepción del verificador no es un veredicto de aceptación (OpenAI la trata como resultado desconocido). [D: OA2]
- [ ] Un verificador del mismo modelo comparte sesgos: no lo vendas como independencia total. [E]
- [ ] Un revisor extra no está probado como mejora universal: mide en tu caso. [O] La cifra «−8 % con un segundo revisor» que circula (Marmelab) no aparece en su fuente primaria: no la uses (`fuentes.md`).

## 7. Intervención humana
- [ ] Escalado por umbral de fallos (reintentos o acciones) y por acción de alto riesgo, irreversible o económica. [O: OA1]
- [ ] Una pregunta bloqueante no se hace con trabajo sin despachar. [E]

## 8. Presupuesto
- [ ] Tope de turnos, tiempo, tokens y dinero por unidad y por sprint. [M-int: A6, el uso de tokens explica el 80 % de la varianza en BrowseComp]
- [ ] Modelo por rol: el más barato que pase la evaluación. [O: OA1]
- [ ] Tope de agentes simultáneos como **política** de cuenta y de máquina; más disco y RAM. [E]

## 9. Recibos y observabilidad
- [ ] Cada invocación deja recibo: encargo, herramientas, coste, resultado, postcondición. Registro de solo añadir, sin contenido sensible. [O, E]
- [ ] Se reconstruye qué pasó sin la conversación.

## 10. Evaluación del propio harness
- [ ] 20-50 tareas reales con resultado verificable antes de optimizar. [O: A8]
- [ ] Comparaciones con las mismas herramientas para todos y varias repeticiones (pass^k si importa la consistencia). [O: A8; E]
- [ ] Cada pieza codifica una suposición sobre lo que el modelo no sabe: al cambiar de modelo, ablación y retirada de lo que sobra. [O: A3]
