# Prototipo SE-493 — Efectos dudosos: qué verías

> **Simulado: las órdenes no existen hasta S1.** Todo lo de abajo es texto de ejemplo.
> Los datos (horas, identificadores, commits) están **inventados**. «#1500» viene del texto literal de las escenas que confirmaste y aquí es solo una etiqueta de ejemplo; los demás PR usan números ficticios (#9001, #9002).
> Sirve para que confirmes o rechaces qué te diría Savia, no cómo está hecho por dentro.

Idea en una frase: si Savia pide algo con efecto fuera (por ejemplo fusionar un PR) y no sabe si salió bien, **no lo repite**. Primero comprueba; si no puede, espera un plazo; si sigue sin saberlo, te pregunta.

---

## Escena 1 — La red cae antes de la respuesta

Savia pidió fusionar un PR y se cortó la conexión antes de saber si GitHub lo aceptó.

**Lo que ves en pantalla:**

> El merge de #1500 quedó dudoso: la petición salió pero no sé si GitHub lo aceptó. Lo compruebo antes de repetir nada.

Lo que pasa después depende de la comprobación y del **plazo de espera** (para un merge, 5 minutos desde que salió la petición):

**Si la comprobación confirma que GitHub sí lo aplicó** (en cualquier momento), Savia lo marca como hecho y guarda el recibo:

> El merge de #1500 sí se hizo. Quedó marcado como hecho, con su commit `abc1234` (ejemplo).

**Si la comprobación no concluye o aún no ve el merge, y el plazo no ha pasado**: el efecto sigue **en vuelo**. No se repite ni se da por fallido; Savia vuelve a comprobar más tarde.

> El merge de #1500 sigue en vuelo (salió hace 2 minutos). No lo repito; vuelvo a comprobarlo cuando pase el plazo.

**Si pasado el plazo la comprobación sigue sin concluir** (por ejemplo, sigue sin red): no repite nada. El efecto pasa a «en revisión» y lo verás como en la escena 2.

---

## Escena 2 — Por la mañana, un efecto en revisión

**Lo que lees:**

> 1 efecto en revisión: publicación del informe, dudoso desde las 03:12. ¿Lo doy por hecho o por fallido?

Opciones que se te ofrecen:

1. **Volver a comprobarlo.** Savia mira otra vez en el servicio. Si ahora la comprobación concluye, el resultado lo pone la comprobación, no quien lo pide. Esta vía la puede usar también un agente, porque no concede nada que la comprobación no pruebe. Solo vale para efectos que pidió este mismo registro.
2. **Darlo por hecho tú** (has comprobado que el informe está publicado).
3. **Darlo por fallido tú** (has comprobado que no está).

Las opciones 2 y 3 exigen **tu permiso firmado, de un solo uso**, del mismo tipo que el de fusionar. Un agente no puede emitirlo ni usar esta vía. Es la única vía cuando la comprobación no concluye, o cuando el efecto no lo pidió este registro (lo hizo otra instalación u otra persona).

Mientras no se resuelva, **nada se repite**. La decisión queda registrada con la fecha, quién la tomó, por qué vía y con qué prueba.

---

## Escena 3 — Dos agentes a la vez sobre el mismo PR

Dos agentes intentan fusionar el mismo PR a la vez. Solo uno lo pide.

**El agente que gana:** sigue y hace la petición.

**El agente que pierde recibe:**

> ya en curso

No hace nada más. No reintenta ni espera a que el otro falle.

---

## Salida de ejemplo — reconciliar un registro con tres efectos

Registro de ejemplo (inventado) con un efecto hecho, uno fallido y uno dudoso. `reconcile` mira **una clave por llamada**, así que son tres llamadas, cada una con su código de salida. **Ninguna ejecuta ni repite el efecto.**

Cada llamada imprime una línea `RESULTADO id-del-efecto id-de-ejecución commit`; debajo va lo mismo en llano.

```
$ effect-ledger.py reconcile ejemplo/repo-a#9001      # SIMULADO — ejemplo, no datos reales
ALREADY_SUCCEEDED eff-0001 run-0001 abc1234…(ejemplo)                    [salida 7]
  en llano:  ya estaba hecho. Recibo: commit abc1234, fusionado por "operadora-ejemplo".

$ effect-ledger.py reconcile ejemplo/repo-a#9002      # SIMULADO
NOT_SENT eff-0002 run-0001 -                                             [salida 0]
  en llano:  este registro no tiene ningún envío pendiente ni hecho para ese PR.
             Aquí, porque la comprobación vio pasado el plazo que el merge no ocurrió.
             No significa «adelante»: pedirlo otra vez pasa de nuevo por la reserva,
             que vuelve a comprobar antes de enviar nada.

$ effect-ledger.py reconcile informe:ejemplo-semanal  # SIMULADO
NEEDS_REVIEW eff-0003 run-0002 - review_origin=dispatched                [salida 4]
  en llano:  dudoso desde las 03:12 (ejemplo). La comprobación no pudo concluir
             y el plazo ya pasó. NO se repite. Necesita resolverse (escena 2).
```

Lo que Savia te enseñaría juntando las tres (resumen informativo, no es una orden):

```
1 hecho, 1 no enviado por este registro, 1 en revisión. Nada se ha repetido.
```

En S1 la única operación registrada es el merge de PR. El informe de la tercera fila ilustra cómo se vería otra operación cuando exista.

Qué significa cada resultado, en llano:

| Resultado | Lo que quiere decir | ¿Se puede volver a pedir? |
|---|---|---|
| `ALREADY_SUCCEEDED` | Está hecho y hay recibo. | No hace falta. |
| `RECONCILED` | Estaba dudoso y la comprobación acaba de confirmar que se hizo. | No hace falta. |
| `IN_FLIGHT` | Salió hace poco o lo está pidiendo otro; aún no se sabe. | **No**; se espera al plazo. |
| `NOT_SENT` | Este registro no tiene envío pendiente ni hecho: nunca se pidió, se preparó y no salió, o se comprobó que no ocurrió. Si el PR aparece fusionado, lo hizo otro. | Solo pasando otra vez por la reserva, que comprueba antes. |
| `NEEDS_REVIEW` | No se sabe, o lo hizo alguien ajeno a este registro. | **No**, hasta que se resuelva (escena 2). |

Los números `[salida N]` son códigos que leen otros programas; tú no tienes que usarlos.

---

## Lo que este prototipo NO enseña

- No deshace ningún efecto: si algo ocurrió, ocurrió.
- No repite algo dudoso aunque la red haya fallado.
- No hay todavía ninguna orden real: todo esto es una simulación para que decidas si es lo que querías.
