# SE-514 S0 — Medición de partida y decisión

Prerregistro: `SE-514-S0-prerregistro.md`, commit `c1812531289f` (anterior a la medición). Solo cifras agregadas: ningún texto de pregunta, nombre de proyecto ni contenido de sesión sale de la máquina donde se midió.

## Fijado

| Pieza | Valor |
|---|---|
| Savia leída | `origin/main` `7321af6b7e36` |
| Instrumento `medir.py` (Savia Labs) | SHA-256 `5241e83176ca486d5b5acc388b6a66a38c17fe78850942d3cef1afe7cde2888b`, commit de Labs `32e0a9483b32`; sus 15 pruebas pasan |
| Fixture del dominio piloto | `projects/soul-continuity/tests/attention/fixtures/piloto-s0.json`, SHA-256 `1088e53f37c591c0a6fa39646d8e96291a363e689d56adacf4e90d6a3f7d0a98` |
| Test del dominio piloto | `projects/soul-continuity/tests/attention/piloto-s0.test.ts`, SHA-256 `76014fb1621271d69bf4812fe8d5c31e2e2607c16183b6f240636f0e0ac4b57d` |
| Ventana | 2026-11-08 a 2026-11-21, 14 días locales (+01:00); el último día está incompleto |

## Observado

### Peticiones por fuente (14 días)

| Fuente que lee el instrumento | Registros | Peticiones distintas (día, objeto, permiso) | Días con datos |
|---|---|---|---|
| Preguntas interactivas de agentes (Claude Code) | 126 | 126 | 12 |
| PRs creadas (cuatro repos) | 167 | 167 | 14 |
| Reconciliador de PRs (LISTA/REREV) | 8094 | 266 | 14 |
| Lista de pendientes de la persona (instantánea de hoy) | 7 | 7 | 1 |
| «Pendiente (operadora)» en marcas de fin de runs | 3 | 3 | 3 |
| Peticiones de revisión explícitas en GitHub | 1 | 1 | 1 |
| **Total** | **8398** | **523** | |

- Duplicados: 7875, de ellos **47 entre fuentes** y 7828 de la misma fuente. El reconciliador escribe cada petición una media de 30 veces (8094 / 266).
- Preguntas de agentes por día, ordenadas: 0, 0, 1, 5, 6, 8, 9, 10, 10, 14, 15, 16, 16, 16. Media 9,0; mediana 9,5.
- **Preguntas de agentes repetidas el mismo día: 0 de 126 en esta muestra.** El criterio es el hash del contenido exacto: dos preguntas iguales con otras palabras no se detectan.
- Sin el reconciliador: 304 peticiones, **0 duplicados entre fuentes**; 1 PR vista en dos fuentes en la ventana (57 con el reconciliador).
- Las 47 duplicaciones entre fuentes son PRs: la misma PR creada en GitHub y marcada lista por el reconciliador el mismo día, más la lista de pendientes.

### Dominio piloto contra la cola existente

`node --experimental-strip-types --test tests/attention/piloto-s0.test.ts`: **8 de 8 en verde**. Cada test se comprobó mutando el valor esperado del fixture (6 de 6 mutaciones fallan). En el código, quitar la regla «un permiso va solo» la detecta X1; la fuente se restauró después.

| Id | Cola de S1/S2 (main) | B0: agrupar por (objeto, permiso), sin agente |
|---|---|---|
| C1 dos agentes, misma decisión | 1 tarjeta; una respuesta resuelve las dos | 1 petición; no contesta nada |
| C2 permiso a las 23:30 | 0 visibles en descanso, `EN_ESPERA`, visible a las 9:05, sin ejecutar | No sabe de descanso ni de espera |
| C3 versión cambiada | `VERSION_CAMBIADA` y se enseña la actual | No sabe de versiones |
| X1 dos permisos, mismo texto | 2 tarjetas; una respuesta resuelve solo la suya | **1 petición**: el instrumento da a toda pregunta el permiso `decision`, así que une dos permisos distintos (incumple AC-4) |
| X2 PR re-emitida 3 veces | 1 petición, 2 duplicadas | 1 petición |
| H1 misma PR por dos fuentes | **2 peticiones**: solo une misma fuente y mismo id | 1 petición |

### Estado del código de SE-514

- S1 (`cola.ts`, #1519) y S2 (`preguntas.ts`, #1534) están en `main` desde el 2026-11-11 y el 2026-11-12. Se fusionaron antes de que existiera esta línea base, que es la entrada de S1 según la spec.
- `construirCola`, `Preguntas` y `dePreguntasAgentes` no tienen ningún llamante fuera de `src/attention/` y sus pruebas (búsqueda en `projects/` y `scripts/`). El servidor de Soul importa del módulo solo la política de avisos.
- La entrada de S2 es «SE-513 S1»; SE-513 está `RETIRED`.

## Decisión según el prerregistro

| Regla | ¿Se cumple? | Datos |
|---|---|---|
| NG-1 dos o más fuentes sin registro legible | **Sí** | De las siete fuentes de la spec, el instrumento no lee cinco: tarjeta de aprobación, avisos de Soul, relevo nocturno, «Esperan algo de ti» y avisos de runs. Los pendientes de la mañana solo se aproximan por las marcas de fin. Tampoco lee los diálogos `ask` de OpenCode |
| NG-2 duplicación entre fuentes < 5 % y 0 preguntas repetidas | No, tal como está escrita | Sin re-emisiones: 47 / 523 = **9,0 %**. Las preguntas repetidas sí son 0 de 126 |
| NG-3 B0 iguala a la cola | No | La cola da C2, C3, X1 y X3, que B0 no da. B0 gana en H1 |
| NG-4 integrado sin consumidor | **Sí** | Ningún llamante (ver arriba) |

**Resultado: MORE_EVIDENCE (NG-1).** AC-7 queda **NO MEDIBLE** hasta que las fuentes sin registro dejen uno legible. S2 no puede afirmar que reduce interrupciones. Además se cumple NG-4: no se abre S3 hasta conectar S1/S2 a un consumidor real. Qué hacer con esto lo decide la operadora.

## Inferido

- El volumen pesa más que el solape. Llegan unas 22 peticiones distintas al día sin el reconciliador, y la duplicación entre fuentes está entera en las PRs (GitHub y reconciliador). Las preguntas de agentes no se repiten tal cual. El argumento de la escena 1 (tres agentes preguntan lo mismo) no tiene apoyo en esta muestra, aunque el criterio de contenido exacto no lo descarta.
- Lo que la cola aporta frente a B0 es lo que tiene garantías: espera sin respuesta, versión y permisos que no se unen. Lo que aporta B0 frente a la cola es unir la misma PR entre fuentes. Es lo que la escena 1 pide y hoy no hace (H1).
- NG-2 depende de cómo se lea «sin las re-emisiones». Tal como está escrita da 9,0 % y no se cumple. Si se excluye el reconciliador entero, da 0 % y se cumpliría. Se aplica la regla escrita. La ambigüedad va a Desviaciones.

## No verificado

- Las cinco fuentes de NG-1 y los diálogos `ask` de OpenCode.
- Cuántas peticiones vio de verdad la persona y con cuánto retraso. Un registro del reconciliador no es un aviso entregado.
- Esperas falsas: preguntas que una lectura barata habría resuelto («antes de preguntar, mirar»). No hay registro, así que la cifra no es cero, es desconocida.
- Preguntas de agentes que dicen lo mismo con otras palabras.
- Qué preguntas vinieron de sesiones con persona delante y cuáles de trabajos lanzados.
- La cuenta de PRs creadas como petición de merge es una sobrecuenta conocida: incluye PRs cerradas el mismo día.

## Desviaciones del prerregistro

- La redacción de NG-2 («sin las re-emisiones del reconciliador») admite dos lecturas; se aplicó la literal. No cambia el resultado, que decide NG-1.
- NG-4 se conocía al escribir el prerregistro: la búsqueda de llamantes se hizo antes, al leer el código. Se dejó como regla igualmente y se declara aquí.
- El fixture se ajustó antes del commit del prerregistro: textos de pregunta explícitos y versión compuesta de la tarjeta. Después de ese commit no ha cambiado.

## Fuera de esta entrega

La matriz de rutas de efecto, el desglose del recall, el soporte de cambio en caliente por harness y las sondas P10–P15 son del S0 de SE-515 (`SE-515-S0-auditoria-linea-base.md`, ya en `main`). No se rehicieron aquí. No se ha tocado ni el prototipo ni su confirmación, ni el `status` de la spec, ni `planning-state.json`.
