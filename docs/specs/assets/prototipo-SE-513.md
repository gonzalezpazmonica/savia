# SE-513 — Prototipo: cambios de prioridad que no se pierden

> **Esto es un prototipo para que lo confirmes o lo rechaces. Nada de esto está construido.**
> - Los textos de Savia son los de las escenas que confirmaste, tal cual.
> - La salida de la cola es **simulada: la orden no existe hasta S1**.
> - Los trabajos, horas y números son un **ejemplo inventado**, no datos reales.

Palabras que aparecen:

- **ADMITIDO** (`ADMITTED`): Savia guardó tu cambio y tiene un dueño. Aún no sabe si el trabajo lo ha incorporado.
- **APLICADO** (`APPLIED_TO_PLAN`): hay una prueba de que el trabajo lo incorporó a su plan.
- **NO SÉ** (`UNKNOWN`): no hay prueba. Savia nunca lo dirá como «hecho».

---

## Escena 1 — 11:20, tres agentes trabajando

Hay tres trabajos: «Informe semanal», «Arreglo de CI» y «Migración de datos». El del informe está a mitad de una suite de pruebas.

**Tú:** deja lo del informe, primero el arreglo de la CI

**Savia:** Anotado. El agente del informe está a mitad de una suite; lo verá al terminarla, en unos seis minutos. Los otros dos no cambian.

*(seis minutos después)*

**Savia:** Aplicado: el informe queda en pausa.

Cola en ese momento (**simulado**):

```
$ bash scripts/attention-queue.sh list        # EJEMPLO, no existe hasta S1
cambio  texto                                  estado      desde   trabajo afectado
#7      informe en pausa, primero arreglo CI   ADMITIDO    11:20   Informe semanal
```

Seis minutos después:

```
cambio  texto                                  estado      desde   trabajo afectado
#7      informe en pausa, primero arreglo CI   APLICADO    11:20   Informe semanal  (prueba: el plan del agente ya lo recoge, 11:26)
```

---

## Escena 2 — mandas el mismo cambio dos veces

No viste respuesta y lo repites a las 11:22.

**Tú:** deja lo del informe, primero el arreglo de la CI

**Savia:** Ya lo tenía anotado (a las 11:20). Lo trato como uno solo; sigue pendiente de que el agente llegue al final de su suite.

```
cambio  texto                                  estado      desde   repetido
#7      informe en pausa, primero arreglo CI   ADMITIDO    11:20   1 vez (11:22), no cuenta como otro
```

---

## Escena 3 — la máquina se reinicia justo después de tu mensaje

**Tú (11:20):** deja lo del informe, primero el arreglo de la CI
*(11:20:03 la máquina se reinicia)*

Al volver (11:24):

**Savia:** Hemos tenido un reinicio. Tu cambio de las 11:20 sigue en la cola; no hace falta repetirlo.

```
cambio  texto                                  estado      desde   notas
#7      informe en pausa, primero arreglo CI   ADMITIDO    11:20   recuperado tras el reinicio
```

---

## Escena 4 — pides adelantar una tarea que publica algo

**Tú:** adelanta la publicación del informe

**Savia:** La adelanto en la cola. Publicar sigue necesitando tu permiso; no lo doy por concedido.

```
cambio  texto                          estado      permiso para publicar
#8      adelantar publicar informe     ADMITIDO    PENDIENTE (lo pide a la persona antes del efecto)
```

Admitir el cambio solo mueve el orden. No abre ningún permiso.

---

## Escena 5 — un agente no puede demostrar que lo incorporó

El agente de la migración no informa de su plan, así que Savia no tiene cómo comprobarlo.

**Tú:** la migración, después de la CI

**Savia:** Anotado. No sé si lo ha aplicado; lo confirmo cuando termine su paso.

```
cambio  texto                          estado      motivo
#9      migración después de la CI     NO SÉ       el agente no da señal de haberlo incorporado
```

Cuando termina su paso:

**Savia:** Ha terminado su paso. Antes de empezar el siguiente ha seguido el orden nuevo: aplicado.

(Si en cambio no se pudiera comprobar, el estado seguiría siendo NO SÉ. Nunca pasa a APLICADO sin prueba.)

---

## Tabla completa de la cola (todos los estados, simulado)

```
$ bash scripts/attention-queue.sh list --all    # EJEMPLO inventado, no existe hasta S1
cambio  texto                                  estado      desde
#7      informe en pausa, primero arreglo CI   APLICADO    11:20
#8      adelantar publicar informe             ADMITIDO    11:31
#9      migración después de la CI             NO SÉ       11:34
```

---

## Qué tienes que decidir mañana

1. ¿Te sirven los tres estados (ADMITIDO / APLICADO / NO SÉ) y las frases de Savia? ¿Falta algún caso?
2. ¿Es correcto que repetir un cambio no lo duplique y que Savia te lo diga?
3. ¿Te vale que «publicar» siga pidiendo permiso aunque adelantes la tarea?
