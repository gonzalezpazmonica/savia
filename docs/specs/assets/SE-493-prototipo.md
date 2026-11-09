# Prototipo SE-493 — Efectos dudosos: qué verías

> **Simulado: las órdenes no existen hasta S1.** Todo lo de abajo es texto de ejemplo.
> Los datos (números de PR, horas, identificadores) están **inventados**; no son datos reales.
> Sirve para que confirmes o rechaces qué te diría Savia, no cómo está hecho por dentro.

Idea en una frase: si Savia pide algo con efecto fuera (por ejemplo fusionar un PR) y no sabe si salió bien, **no lo repite**. Primero comprueba; si no puede, te pregunta.

---

## Escena 1 — La red cae antes de la respuesta

Savia pidió fusionar un PR y se cortó la conexión antes de saber si GitHub lo aceptó.

**Lo que ves en pantalla:**

> El merge de #1500 quedó dudoso: la petición salió pero no sé si GitHub lo aceptó. Lo compruebo antes de repetir nada.

**Si la comprobación confirma que GitHub sí lo aplicó**, Savia lo marca como hecho y guarda el recibo:

> El merge de #1500 sí se hizo. Quedó marcado como hecho, con su commit `abc1234` (ejemplo).

**Si la comprobación no concluye** (sigue sin red): no repite nada. El efecto pasa a «en revisión» y lo verás como en la escena 2.

---

## Escena 2 — Por la mañana, un efecto en revisión

**Lo que lees:**

> 1 efecto en revisión: publicación del informe, dudoso desde las 03:12. ¿Lo doy por hecho o por fallido?

Opciones que se te ofrecen:

1. **Darlo por hecho** (tú has comprobado que el informe está publicado).
2. **Darlo por fallido** (tú has comprobado que no está).

Mientras no elijas, **nada se repite**. Cuando eliges, tu decisión queda registrada con la fecha y quién la tomó.

---

## Escena 3 — Dos agentes a la vez sobre el mismo PR

Dos agentes intentan fusionar el mismo PR a la vez. Solo uno lo pide.

**El agente que gana:** sigue y hace la petición.

**El agente que pierde recibe:**

> ya en curso

No hace nada más. No reintenta ni espera a que el otro falle.

---

## Salida de ejemplo — reconciliar un registro con tres efectos

Registro de ejemplo (inventado) con un efecto hecho, uno fallido y uno dudoso. La orden comprueba cada uno y dice qué hay. **No ejecuta ni repite ningún efecto.**

```
$ effect-ledger.py reconcile --all      # SIMULADO — ejemplo, no datos reales

EFECTO 1   fusionar PR ejemplo/repo-a#1500
  estado:      HECHO
  resultado:   ALREADY_SUCCEEDED
  recibo:      commit abc1234 (ejemplo), fusionado por "operadora-ejemplo"
  qué pasa:    nada que hacer; ya está hecho.                       [salida 7]

EFECTO 2   fusionar PR ejemplo/repo-a#1501
  estado:      FALLIDO
  resultado:   NOT_SENT
  prueba:      el PR sigue abierto, sin fusión pendiente, y pasó el plazo de espera
  qué pasa:    este registro no hizo el efecto. Se puede volver a pedir. [salida 0]

EFECTO 3   publicar informe de ejemplo
  estado:      DUDOSO
  resultado:   NEEDS_REVIEW   (origen: dispatched)
  dudoso desde: 03:12 (ejemplo)
  prueba:      la comprobación no pudo concluir (sin respuesta del servicio)
  qué pasa:    NO se repite. Necesita tu decisión: hecho o fallido.   [salida 4]

RESUMEN: 1 hecho, 1 fallido, 1 en revisión. Nada se ha repetido.
```

Qué significa cada línea, en llano:

| Resultado | Lo que quiere decir | ¿Se puede repetir? |
|---|---|---|
| `ALREADY_SUCCEEDED` | Está hecho y hay recibo. | No hace falta. |
| `NOT_SENT` | Se comprobó que no ocurrió. | Sí. |
| `NEEDS_REVIEW` | No se sabe. | **No**, hasta que lo compruebes o decidas tú. |

Los números `[salida N]` son códigos que leen otros programas; tú no tienes que usarlos.

---

## Lo que este prototipo NO enseña

- No deshace ningún efecto: si algo ocurrió, ocurrió.
- No repite algo dudoso aunque la red haya fallado.
- No hay todavía ninguna orden real: todo esto es una simulación para que decidas si es lo que querías.
