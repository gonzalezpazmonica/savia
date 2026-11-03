# Prueba en dispositivo real: consulta, reinicio, pantalla de bloqueo y desemparejado (SE-490, AC-4b)

> Para quien opera el gemelo, en su propio móvil Android. Unos 10 minutos de trabajo activo; la prueba de Doze sin cable añade una espera de alrededor de una hora con el teléfono quieto.
> Cubre la parte de AC-4b que solo se comprueba en un teléfono de verdad: la consulta cada 5 minutos en segundo plano y en Doze, tras reiniciar, la pantalla de bloqueo con el nivel `recuentos` y la revocación del token al desemparejar.
> El resto de AC-4b (presupuesto de avisos, modos de atención, test de puertos, texto libre) tiene tests automáticos y no se repite aquí.

## Antes de empezar

- [ ] En el portátil, Soul responde: `node bin/soul.mjs status` sin errores y `node bin/soul.mjs serve` en marcha.
- [ ] La VPN del operador está activa en el portátil y en el móvil.
- [ ] El móvil tiene una versión de la app de Savia Space con la pantalla **Continuidad** y está emparejado en **modo directo** con `soul pair`. En modo Space, la revocación se hace desde Space y la sección 4 no aplica tal cual.
- [ ] Hay al menos una regla de aviso activada (por ejemplo, reunión próxima), para que llegue algún aviso.
- [ ] En el móvil, **Continuidad → Avisos → En este teléfono**:
  - «Mantener la consulta activa»: **encendido**;
  - «Mostrar asuntos en la pantalla de bloqueo»: **apagado**.
- [ ] Anota la versión de Android y el fabricante (sin modelo exacto ni número de serie). Algunos fabricantes cierran apps en segundo plano por su cuenta; si algo falla, eso es lo primero que hay que mirar.

Con cable (opcional): `adb devices` lista el teléfono y conoces el nombre del paquete de la app (`adb shell pm list packages | grep -i savia`). En las órdenes de abajo aparece como `<paquete>`.

**Cómo leer la consulta.** Mientras la consulta está activa hay una notificación persistente del canal «Conexión con Soul»:

- «Soul conectado · último contacto HH:MM» si la última consulta fue bien;
- «Sin contacto con tu equipo desde HH:MM» tras dos fallos seguidos o si el último éxito tiene más de 10 minutos;
- «Sin contacto con tu equipo todavía» si aún no hubo ninguna consulta buena.

La hora de «último contacto» es el dato que se usa en toda la guía.

## 1. Consulta cada 5 minutos

### 1a. App en segundo plano (sin Doze)

1. Abre Continuidad y pulsa **Consultar ya**. Anota la hora de «último contacto».
2. Vuelve al escritorio con la app abierta en segundo plano (no la cierres desde recientes). Deja la pantalla encendida o enciéndela cada pocos minutos.
3. Durante 12 minutos, mira la notificación persistente.

| Paso | Resultado esperado | OK | FALLO |
|---|---|---|---|
| 1a.1 | La hora de «último contacto» avanza al menos dos veces, con no más de 6 minutos entre una y otra (5 de periodo y margen de red) | [ ] | [ ] |
| 1a.2 | La notificación persistente no desaparece en ningún momento | [ ] | [ ] |
| 1a.3 | Con `adb shell dumpsys activity services <paquete>` aparece `ContinuityService` (solo con cable) | [ ] | [ ] |

### 1b. Doze con cable (adb)

Así se fuerza Doze profundo en unos segundos:

```
adb shell dumpsys battery unplug
adb shell dumpsys deviceidle force-idle
adb shell dumpsys deviceidle get deep        # debe decir IDLE
```

1. Apaga la pantalla y espera 15 minutos sin tocar el teléfono.
2. Enciende la pantalla y mira la notificación persistente antes de abrir nada.
3. Sal de Doze:

```
adb shell dumpsys deviceidle unforce
adb shell dumpsys battery reset
```

4. Repite con la app exenta de optimización de batería (**Continuidad → Avisos → Ajustes de optimización de batería**) y anota cuál de las dos pasadas es cuál. Para comprobar la exención: `adb shell dumpsys deviceidle whitelist | grep <paquete>`.

| Paso | Resultado esperado | OK | FALLO |
|---|---|---|---|
| 1b.1 | Al encender la pantalla, la notificación es honesta: o «último contacto» tiene 10 minutos o menos, o dice «Sin contacto con tu equipo desde HH:MM». Nunca «conectado» con una hora más vieja de 10 minutos | [ ] | [ ] |
| 1b.2 | Tras salir de Doze, «último contacto» se actualiza en 5 minutos como mucho, sin abrir la app | [ ] | [ ] |
| 1b.3 | Hueco máximo medido entre dos «último contacto» durante Doze: ___ min sin exención, ___ min con exención (dato, no aprobado ni suspenso) | — | — |

En Doze el sistema solo deja red en sus ventanas de mantenimiento: el periodo de 5 minutos se alarga. Por eso 1b.3 es una medida. Lo que se exige es que la app no mienta (1b.1) y que recupere sola (1b.2).

### 1c. Doze sin cable

1. Desenchufa el cargador, pulsa **Consultar ya**, anota la hora y apaga la pantalla.
2. Deja el teléfono quieto, boca abajo, sin tocarlo, durante al menos 60 minutos. Doze entra solo tras un rato con la pantalla apagada, sin cargar y sin movimiento; cuánto tarda depende del fabricante.
3. Enciende la pantalla y mira la notificación persistente antes de desbloquear.

| Paso | Resultado esperado | OK | FALLO |
|---|---|---|---|
| 1c.1 | Igual que 1b.1: la notificación dice la verdad sobre el contacto | [ ] | [ ] |
| 1c.2 | En 5 minutos con la pantalla encendida, «último contacto» se pone al día sin abrir la app | [ ] | [ ] |
| 1c.3 | La notificación persistente sigue ahí tras la hora de espera (si desapareció, el sistema o el fabricante mató el servicio) | [ ] | [ ] |

## 2. Tras reiniciar el teléfono

### 2a. Con «Mantener la consulta activa» encendido

1. Reinicia el teléfono y desbloquéalo una vez. No abras la app.
2. Espera 6 minutos.

| Paso | Resultado esperado | OK | FALLO |
|---|---|---|---|
| 2a.1 | Vuelve la notificación persistente sin abrir la app | [ ] | [ ] |
| 2a.2 | «último contacto» muestra una hora posterior al reinicio | [ ] | [ ] |

### 2b. Con «Mantener la consulta activa» apagado (caso negativo)

1. Apaga el ajuste, reinicia y desbloquea. No abras la app y espera 6 minutos.
2. Abre la app y entra en Continuidad.

| Paso | Resultado esperado | OK | FALLO |
|---|---|---|---|
| 2b.1 | Sin abrir la app, no hay notificación persistente: la consulta no arranca sola | [ ] | [ ] |
| 2b.2 | Al abrir Continuidad, la consulta arranca y aparece la notificación | [ ] | [ ] |

Vuelve a encender «Mantener la consulta activa» antes de seguir.

## 3. Pantalla bloqueada con el nivel `recuentos`

1. En **Continuidad → Avisos → Nivel de detalle**, elige `recuentos`. La cabecera de Continuidad debe decir «Detalle: recuentos».
2. Provoca un aviso con un asunto que puedas reconocer y que no sea real: por ejemplo, una reunión de prueba dentro de 20 minutos con el asunto `PRUEBA-ASUNTO-7Q` y un invitado ficticio llamado `Nombre Prueba`, en una fuente que lea Soul.
3. Bloquea el teléfono y espera a que llegue el aviso (hasta 5 minutos más el intervalo de lectura de la fuente).
4. Con el aviso en pantalla, enciende «Mostrar asuntos en la pantalla de bloqueo» y vuelve a bloquear.

| Paso | Resultado esperado | OK | FALLO |
|---|---|---|---|
| 3.1 | En la pantalla de bloqueo, el aviso solo da cifras y tipo (por ejemplo «1 aviso» o «2 avisos, 1 alerta») | [ ] | [ ] |
| 3.2 | No aparece `PRUEBA-ASUNTO-7Q`, ni `Nombre Prueba`, ni ningún otro asunto o nombre | [ ] | [ ] |
| 3.3 | Desbloqueado, al desplegar la notificación tampoco aparecen asunto ni nombre | [ ] | [ ] |
| 3.4 | Con «Mostrar asuntos» encendido sigue sin aparecer el asunto: el ajuste nunca supera el nivel | [ ] | [ ] |
| 3.5 | Con cable: `adb shell dumpsys notification --noredact \| grep -c PRUEBA-ASUNTO-7Q` devuelve `0` | [ ] | [ ] |

Al terminar, apaga «Mostrar asuntos», borra la reunión de prueba y deja el nivel donde lo tuvieras.

## 4. Desemparejar: el token deja de valer

1. En el portátil, lista los dispositivos y anota el id del móvil (no lo copies en los resultados):

```
node bin/soul.mjs devices
node bin/soul.mjs unpair <id>
```

   La segunda orden debe responder «Desemparejado <id>: su token deja de valer.»
2. En el móvil, abre Continuidad y pulsa **Consultar ya** (o espera la siguiente consulta).
3. En el portátil, vuelve a ejecutar `node bin/soul.mjs devices`.
4. Repite `unpair` con el mismo id.

| Paso | Resultado esperado | OK | FALLO |
|---|---|---|---|
| 4.1 | La app muestra «Este teléfono fue revocado en tu equipo. Se borraron su credencial y su clave: vuelve a emparejar.» o, en modo directo, «El emparejamiento con tu portátil caducó o el portátil ya no lo reconoce…». Las dos piden emparejar de nuevo; ninguna pantalla muestra datos nuevos | [ ] | [ ] |
| 4.2 | La consulta se para: «último contacto» no vuelve a avanzar y ninguna notificación dice «conectado». Con el mensaje de revocado, además desaparecen los avisos que hubiera | [ ] | [ ] |
| 4.3 | `devices` muestra el móvil con «(revocado)» | [ ] | [ ] |
| 4.4 | Reiniciar `serve` no le devuelve el acceso: tras reiniciarlo, **Consultar ya** sigue pidiendo emparejar | [ ] | [ ] |
| 4.5 | Volver a emparejar exige un `soul pair` nuevo, que da otro id; el antiguo sigue «(revocado)» | [ ] | [ ] |

El token que muestra `soul pair` es secreto: no lo pegues en notas, capturas ni resultados.

## Cómo anotar los resultados

Copia esta plantilla en el registro del piloto. Solo casillas, minutos y la versión de Android.

```
Prueba en dispositivo SE-490 AC-4b
Fecha: AAAA-MM-DD
Android: <versión mayor>   Fabricante: <marca>   Modo: directo
Exención de batería en 1b: con y sin
1a.1 OK|FALLO  1a.2 OK|FALLO  1a.3 OK|FALLO|sin cable
1b.1 OK|FALLO  1b.2 OK|FALLO  1b.3 hueco sin exención __ min, con exención __ min
1c.1 OK|FALLO  1c.2 OK|FALLO  1c.3 OK|FALLO
2a.1 OK|FALLO  2a.2 OK|FALLO  2b.1 OK|FALLO  2b.2 OK|FALLO
3.1 OK|FALLO  3.2 OK|FALLO  3.3 OK|FALLO  3.4 OK|FALLO  3.5 OK|FALLO|sin cable
4.1 OK|FALLO  4.2 OK|FALLO  4.3 OK|FALLO  4.4 OK|FALLO  4.5 OK|FALLO
Fallos: <paso>: <qué se vio, en una frase y sin datos>
```

No anotes:

- direcciones IP, nombres de red o de la VPN, ni el nombre del teléfono;
- el token, la huella del certificado ni el id del dispositivo;
- asuntos, nombres de personas o proyectos, aunque sean de prueba;
- horas de reloj: usa minutos relativos («hueco de 14 min»);
- capturas de la pantalla de bloqueo o de Continuidad. Si una captura es imprescindible para explicar un fallo, que sea con el nivel `recuentos` y revisada antes de compartirla.

Un FALLO en 1b.1, 1c.1, 3.1–3.5 o 4.1–4.4 bloquea AC-4b. Un FALLO en 1c.3 o 2a.x con un fabricante que cierra apps por su cuenta se anota con la marca y se trata aparte: dice algo del teléfono y no necesariamente de la app.
