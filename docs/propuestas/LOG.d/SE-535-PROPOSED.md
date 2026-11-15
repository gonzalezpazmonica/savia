## 2026-11-15 SE-535 PROPOSED

Cliente externo del puente con alcance solo de conversación, en dos slices (S1 puente, S2 cliente). Solo spec: el puente no cambia. Antes de redactar se comprobó con el CLI real que una invocación con herramientas de lectura, sin configuración local y sobre una copia de los ficheros versionados no lee ficheros locales ignorados ni ficheros fuera de la copia. Escenas, prototipo y decisiones D1-D4 pendientes de la operadora.

Revisión independiente (2026-11-15): la barrera de escucha se evalúa también en el alta, el canario lleva control positivo, el cuerpo de `/chat` pasa a lista blanca de campos, los topes definen concurrencia, 5xx, timeout y persistencia, y se añaden AC para enlaces simbólicos y límite de fallos de autenticación (18 AC en S1).

Segunda revisión (2026-11-15): el alta, el listado y la revocación hablan con el puente por su dirección de escucha con TLS y huella (no por bucle local, sin listener de administración); nombre de cliente validado; entorno mínimo del subproceso; canarios en credenciales y entorno; detección de denegación por salida estructurada con inconcluyente = fallo; concurrencia configurable que permite probar la reserva atómica; cota de copia y topes por defecto; reversión coherente con las rutas anónimas; códigos de salida del cliente alineados (24 AC en S1).
