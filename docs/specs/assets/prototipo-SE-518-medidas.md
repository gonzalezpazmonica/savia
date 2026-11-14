# SE-518 S0 — las tres medidas que deciden si el corte C sigue en pie

Spec: `docs/specs/SE-518-pulse-latido.spec.md` (slice S0). Prototipo: `docs/specs/assets/SE-518-prototipo.html`.
Estado: medidas entregadas; **la decisión «C o basta A» es de la operadora** junto con la confirmación del prototipo. Lo de aquí es evidencia y una recomendación.

## Resumen

| Medida | Resultado | Cómo se sabe |
|---|---|---|
| (a) Sonda en macOS sin administrador | Procedimiento y sonda entregados; **no ejecutada en un Mac** (aquí no hay) | Prueba seca con siete escenarios simulados en Linux (`tests/test-se518-s0.bats`). Lo que diría un Mac real queda sin verificar |
| (b) Modos que permite la organización | Cada modo se deriva de comprobaciones concretas; sin Mac no hay respuesta para ninguna organización | Tabla de abajo; la respuesta la da `--active` en el equipo real |
| (c) Lógica reutilizable del bucle actual | 96 de 120 aserciones de su batería de pruebas (80 %) sirven como casos dorados, 62 tal cual y 34 adaptadas | Clasificación por sección (ver método y límites) |

**Recomendación: C sigue en pie, condicionada a (a).** Dos razones, ninguna decisiva por sí sola:

1. El 80 % de la lógica probada del bucle actual se traslada a un planificador puro sin reescribir las reglas, solo su entrada y salida. Eso abarata C.
2. De las ocho clases de fallo de la spec, seis están en el propio código del bucle actual (F1, F4, F5, F6, F7, F8) y no se arreglan sin cambiar su forma: la cuota se lee de texto de un log, no emite ningún evento de fin, la deduplicación de la cola usa el hash del texto, no comprueba el alcance, deduce la vida de un proceso con `ps` y espera pruebas en cola sin tope. F2 y F3 viven fuera de ese script (el workflow del repo y la fusión en serie): esta medida no las confirma ni las descarta.

Lo que haría caer a C y dejar **A** (contratos sobre el bucle actual) es que el equipo de la organización rechace un servicio de usuario ni siquiera en `observar`. Eso solo lo dice la sonda con `--active` en ese equipo. Mientras no corra, el veredicto de (a) es «sin datos», no «viable».

## (a) Sonda en macOS sin administrador

Script: `scripts/pulse-probe-macos.sh` (compatible con el bash 3.2 de macOS: sin `declare -A`, `mapfile` ni `flock`).

Procedimiento, con el usuario normal, sin `sudo` y desde Terminal en el propio Mac (no por `ssh`, porque `launchctl` necesita la sesión gráfica):

1. `bash scripts/pulse-probe-macos.sh --plan` enseña qué ejecutará cada comprobación. No ejecuta nada.
2. `bash scripts/pulse-probe-macos.sh` hace la sonda pasiva (solo lectura). Termina en «sin datos» a propósito: sin cargar un servicio no se sabe si la organización lo permite.
3. `bash scripts/pulse-probe-macos.sh --active` carga un servicio de usuario de prueba (una etiqueta propia, que solo hace `touch` de un fichero temporal), espera hasta 10 s a que se ejecute, lo descarga y borra su plist. Es lo único que escribe fuera del directorio temporal, y se deshace solo, también si se interrumpe con Ctrl-C o `kill` (no con `kill -9`); si `~/Library/LaunchAgents` no existía, lo borra al terminar. Un plist de prueba que no pasa `plutil -lint`, o un servicio que no se ejecuta en 10 s, dan `UNKNOWN`, no `FAIL`: no son un rechazo de la política.
4. Opcional: `--soul-runtime <ruta>`: si la ruta es ejecutable, el intérprete queda en `UNKNOWN` (existe, pero no se ha ejecutado; si sirve para el núcleo se decide en S1) y `observar` no pasa a `PERMITIDO`.

Comprobaciones: intérprete (Python ≥ 3.9 o runtime de Soul), `git`, escritura en `~/Library/LaunchAgents` con un plist válido (`plutil -lint`), carga y ejecución de un servicio de usuario sin `sudo`, bloqueo de fichero por `mkdir` atómico (sin `flock`), CLI del forge (`gh` o `az`), motor de inferencia y, siempre desconocido aquí, el push de prueba.

Regla fail-closed: un dato que no se puede observar es `UNKNOWN` y nunca cuenta como `PASS`. Hay tres casos de macOS que la sonda trata como `UNKNOWN` por diseño, descritos en la documentación de Apple y no comprobados aquí por falta de Mac:

- `python3` y `git` en `/usr/bin` son atajos de las Command Line Tools: sin ellas instaladas, ejecutarlos abre un instalador. La sonda mira `xcode-select -p` antes de ejecutarlos.
- Sin sesión gráfica (por `ssh`) `launchctl bootstrap gui/<uid>` falla aunque la política lo permita: se da `UNKNOWN`, no `FAIL`.
- No hay `plutil` o no se puede validar el plist: `UNKNOWN`.

Código de salida: 0 si `observar` está permitido, 1 si no, 2 si no se determina, 3 si el equipo no es macOS (no es un `PASS`).

**Prueba seca** (esto sí se ha ejecutado): `bash scripts/pulse-probe-macos.sh --simulate <escenario>` con `ok-activo`, `pasivo`, `python-viejo`, `shim-clt`, `sin-motor`, `bloquea-servicio` y `sin-forge`. Comprueba la lógica de veredicto, no el Mac.

## (b) Qué modos permite la política de la organización

La política de una organización no se lee: se observa probando. Cada modo exige un conjunto de comprobaciones:

| Modo | Necesita (todo en `PASS`) | Lo que puede vetar la organización |
|---|---|---|
| `observar` | intérprete, `git`, escritura y carga del servicio de usuario, bloqueo, CLI del forge | Servicios de usuario en segundo plano (gestión de dispositivos), instalar Python o las Command Line Tools |
| `proponer` | lo de `observar` + motor de inferencia | Cualquier motor de inferencia no autorizado |
| `actuar` | lo de `proponer` + push de prueba a una rama `agent/*` | Credenciales de escritura en el forge, ramas protegidas |

Cada modo sale `PERMITIDO` (todo `PASS`), `NO_PERMITIDO` (algo `FAIL`) o `NO_DETERMINADO` (nada falla pero algo es `UNKNOWN`). `actuar` sale siempre `NO_DETERMINADO` mientras el push de prueba lo confirme una persona. «Ningún motor» es válido y deja la instalación en `observar`, aunque se haya elegido `actuar` (lo dice la spec).

Esta tabla **informa la elección del operador; no cambia el defecto**: el modo inicial sigue siendo `observar` (D3). Cuál de las tres filas pasa en la organización concreta de la operadora no se ha medido.

## (c) Lógica reutilizable del bucle actual

**Qué se midió.** El bucle actual es un script bash de una instalación (709 líneas) con su batería de pruebas (477 líneas, 120 aserciones en 23 grupos y sus variantes). No se versiona: es privado de esa instalación y por eso esta medida no se puede reproducir desde el repo; las cifras son de quien midió, no de una prueba independiente. Se contó el parecido con los casos dorados que el planificador puro de SE-518 necesita (estado observado → acción), por la sección de la batería a la que pertenece cada aserción.

**Método y límite.** Clasifiqué por grupo según su cabecera y la lectura de sus casos tipo, no una por una las 120 aserciones. El margen real puede moverse unas pocas aserciones. No se midió por líneas de código porque la decisión y la entrada/salida van mezcladas: la función principal de una pasada tiene 293 líneas que entrelazan ambas. Esa mezcla es precisamente lo que el planificador puro separa.

| Clase | Aserciones | Qué contiene |
|---|---|---|
| **G** tal cual (estado → acción) | 62 (52 %) | Trabajo o revisión vivos no se relanzan (3) · conflicto: integrar una vez por cabeza (4) · revisión que falta, de otra cabeza o sin informe (10) · corrección con tope de 3 rondas y aparcado (6) · doble aprobación: registrar con el nivel mayor, o ya registrada (4) · base apilada fusionada frente a rama reutilizada (4) · actualizaciones automáticas ignoradas (1) · pruebas en rojo sobre la cabeza: no aprobada, corrección, pendiente espera, rojo de la rama principal sin ronda, tras 3 rondas aparcada (25) · aparcada con cabeza nueva: rondas a cero (5) |
| **A** adaptada (la regla vale, la entrada cambia) | 34 (28 %) | Cuota por texto de log → señal tipada (8) · capacidad por memoria y exclusión con otro actor (6) · cola de trabajos (5) · cambio de base de la propuesta apilada (8) · forge caído: fail-closed (1) · «nunca fusiona, aprueba ni fuerza push» como prueba estática (6) |
| **X** no reutilizable | 24 (20 %) | Revisión y tarea de integración de un segundo repositorio privado (13) · planificadora de tareas (4) · dry-run del script (4) · candado de la pasada y herencia por procesos hijos (2) · informe de pendientes (1) |

Total 62 + 34 + 24 = 120. Reutilizable, G + A: 96 (80 %).

**Portabilidad del script actual** (coincidencias en sus 709 líneas): `flock` 4, `date -d` 5, `stat -c` 2, `date -Is` 2, `declare -A` 2 (necesita bash ≥ 4; macOS trae 3.2), `/proc` 1, `sha256sum` 1, `sed -i` 1. En total 18 usos que fallan o cambian en macOS según la documentación de BSD y bash; no se ejecutó en un Mac. La spec ya lo da por hecho (D2: Python estándar ≥ 3.9).

**Clases de fallo de la spec confirmadas en este código.** F1 (cuota deducida con una expresión regular sobre las últimas 40 líneas de un log), F4 (cero líneas que emitan evento o aviso de fin), F5 (la cola deduplica por el hash del texto de la línea), F6 (cero comprobaciones de alcance), F7 (vida por `ps` y un registro de arranques), F8 (con las pruebas pendientes o sin pruebas, «se espera» sin tope). F2 y F3: no verificables en este script.

## Qué no se hizo

- No se ha ejecutado nada en un Mac. Todo lo que dice la sección (a) sobre macOS viene de la documentación de Apple, no de una prueba.
- No se ha medido la política de ninguna organización concreta.
- La confirmación del prototipo no está: la da la operadora. El prototipo usa solo datos inventados y no se ha probado con una persona no técnica (AC-21 sigue abierto).
- No se ha tocado el bucle actual ni se ha empezado S1.
