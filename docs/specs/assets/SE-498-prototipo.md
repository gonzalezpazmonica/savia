# Prototipo SE-498 — Parar todo: qué verías

> **Simulado: las órdenes no existen hasta S1.** Todo lo de abajo es texto de ejemplo.
> Los ejecutores existen; las horas, permisos, identificadores y números de parada están **inventados**. «#1500» viene del texto literal de las escenas que confirmaste y aquí es solo una etiqueta de ejemplo.
> Sirve para que confirmes o rechaces qué te diría Savia, no cómo está hecho por dentro.

Idea en una frase: una sola orden para todo, con acuse de cada uno. Tras una revocación, los permisos de antes dejan de valer. Un agente puede parar, **no reanudar**.

Escenario de ejemplo: cuatro ejecutores (el sprint de merges, los workers, Yema y Soul) y un efecto en vuelo (un merge de #1500). Primero pausas; luego decides revocar. Las escenas 2 y 3 ocurren **después de la revocación**.

---

## Escena 1 — Dices «para todo»

### `pause` — pausar

```
$ savia-control.py pause --reason "revisar el PR #1500"      # SIMULADO — ejemplo

PARADA global (pausa) registrada. Motivo: revisar el PR #1500
  sprint de merges   parado   acuse recibido
  workers            parados  acuse recibido
  Yema               parada   acuse recibido
  Soul               parada   acuse recibido

4 de 4 han parado.
1 efecto estaba en vuelo: merge de #1500, dudoso; queda en revisión.
Los permisos siguen valiendo (pausar no cambia la época). Lo que ya estaba pidiéndose termina su llamada y se anota.
```

### `revoke` — revocar (más fuerte que pausar)

```
$ savia-control.py revoke --reason "credencial sospechosa"   # SIMULADO — ejemplo

REVOCACIÓN global registrada. Época: 6 (antes 5).
4 de 4 han parado. Todos los permisos anteriores a esta época han dejado de valer.
```

Diferencia: **pausar** frena lo nuevo y deja los permisos como están; al reanudar, cada ejecutor vuelve a validar su permiso antes de usarlo. **Revocar** frena y además anula todos los permisos dados hasta ahora (sube la época).

---

## Escena 2 — Un agente con un permiso de ayer intenta seguir

Tras la revocación, un agente prueba con un permiso emitido antes (época 5; la vigente es 6).

**Mientras la parada sigue en pie**, recibe esto, tenga el permiso que tenga:

> Parado: revocación global («credencial sospechosa»). No se produce ningún efecto.   `[salida 6]`

**Después de que reanudes** (escena 3), el mismo permiso sigue sin valer:

> Permiso rechazado: es anterior a la parada (época 5, vigente 6). Hace falta uno nuevo.   `[salida 8]`

El agente no puede evitarlo ni renovarlo él mismo. Si solo hubieras pausado, la época no cambiaría y este segundo mensaje no aparecería.

---

## Escena 3 — Reanudas

### Paso 1: `reconcile` — ver qué quedó en vuelo

```
$ savia-control.py reconcile      # SIMULADO — ejemplo

Efectos abiertos en ámbitos parados: 1
  indeterminado    eff-7f3a   merge de #1500     no se sabe si ocurrió
No se ha ejecutado ningún efecto. Queda 1 indeterminado.          [salida 5]
```

El 5 quiere decir que queda algo sin cerrar: `resume` no procederá hasta que lo aceptes.

### Paso 2: `resume` — reanudar (solo tú)

Un agente que lo intenta recibe:

> No puedo reanudar: hace falta la aprobación de la operadora. No ha cambiado nada.   `[salida 4]`

Tú reanudas por una de dos vías, y en el mismo acto aceptas cada efecto indeterminado **por su identificador**:

- **Aprobando una PR** que lleva el fichero de reanudación con la lista de aceptados (aquí, `["eff-7f3a"]`).
- **Por tu terminal**, tecleando la confirmación. Así se vería:

```
$ savia-control.py resume      # SIMULADO — ejemplo, lo ejecuta la operadora en su terminal

Ámbito: global   parada nº 7
Para confirmar, teclea el ámbito y el número de parada: global 7

Efectos indeterminados del último reconcile: 1
  eff-7f3a   merge de #1500
Para aceptar cada uno, teclea «acepto <id>»: acepto eff-7f3a

Plano de control reanudado (global). Época 6.
Aceptado por la operadora: eff-7f3a, merge de #1500 (sigue sin resolverse en el registro; solo deja de bloquear).

Ejecutores:
  workers            en marcha. No tienen permiso propio: solo los frenaba la parada.
  sprint de merges   sigue parado. Su permiso es de época 5 -> NO vale.
                     Lo levanta un permiso nuevo tuyo:        merge-sprint.sh grant …
  Soul               sigue parada. No tiene permisos que revocar.
                     Su parada solo la levantas tú:           soul resume
  Yema               sigue parada. Su contrato quedó revocado.
                     Reactivarla exige persona en terminal:   <orden de reactivación de Yema>

Estado: REANUDACIÓN INCOMPLETA — faltan 3 pasos tuyos.
```

Si no aceptas `eff-7f3a`, o aceptas un identificador que no está en la lista, `resume` sale con 5, lo dice y no cambia nada.

Puntos que ves aquí en llano:

- Savia **no se salta** las paradas propias de cada ejecutor: te dice cuáles te tocan a ti y con qué orden.
- Si queda un efecto dudoso sin aceptar por ti, `resume` **no procede** y lo lista.
- Aceptar un efecto dudoso no lo resuelve: solo deja de bloquear la reanudación.
- Reanudar no devuelve a la vida permisos anteriores a una revocación.

---

## Lo que este prototipo NO enseña

- No deshace lo irreversible.
- Un agente puede parar, pero no reanudar.
- Parar a un ejecutor concreto sin parar al resto (`quarantine`) queda para S1; aquí solo se simula la parada global.
- No hay todavía ninguna orden real: todo esto es una simulación para que decidas si es lo que querías.
