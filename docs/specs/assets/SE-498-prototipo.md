# Prototipo SE-498 — Parar todo: qué verías

> **Simulado: las órdenes no existen hasta S1.** Todo lo de abajo es texto de ejemplo.
> Los ejecutores, números de PR, horas y permisos están **inventados**; no son datos reales.
> Sirve para que confirmes o rechaces qué te diría Savia, no cómo está hecho por dentro.

Idea en una frase: una sola orden para todo, con acuse de cada uno. Los permisos de antes de la parada dejan de valer. Un agente puede parar, **no reanudar**.

Escenario de ejemplo: cuatro ejecutores (el sprint de merges, los workers, Yema y Soul) y un efecto en vuelo (un merge de #1500).

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
Los permisos siguen valiendo. Lo que ya estaba pidiéndose termina su llamada y se anota.
```

### `revoke` — revocar (más fuerte que pausar)

```
$ savia-control.py revoke --reason "credencial sospechosa"   # SIMULADO — ejemplo

REVOCACIÓN global registrada. Época: 6 (antes 5).
4 de 4 han parado. Todos los permisos anteriores a esta época han dejado de valer.
```

Diferencia: **pausar** frena lo nuevo y deja los permisos como están. **Revocar** frena y además anula todos los permisos dados hasta ahora.

---

## Escena 2 — Un agente con un permiso de ayer intenta seguir

Después de la parada, un agente prueba con un permiso emitido antes (época 5; la actual es 6).

> Permiso rechazado: es anterior a la parada (época 5, vigente 6). Hace falta uno nuevo.

El agente no puede evitarlo ni renovarlo él mismo.

---

## Escena 3 — Reanudas

### Paso 1: `reconcile` — ver qué quedó en vuelo

```
$ savia-control.py reconcile      # SIMULADO — ejemplo

Efectos abiertos en ámbitos parados: 2
  confirmado       publicar nota de ejemplo           ocurrió, con recibo
  indeterminado    merge de #1500                     no se sabe si ocurrió
No se ha ejecutado ningún efecto. Queda 1 indeterminado.
```

### Paso 2: `resume` — reanudar (solo tú)

Un agente que lo intenta recibe:

> No puedo reanudar: hace falta la aprobación de la operadora. No ha cambiado nada.

Tú reanudas (por terminal o aprobando una PR) y aceptas el efecto dudoso por su identificador:

```
$ savia-control.py resume      # SIMULADO — ejemplo, lo ejecuta la operadora

Plano de control reanudado (global).
Aceptado por la operadora: merge de #1500 (sigue sin resolverse en el registro).

Permisos comprobados de nuevo:
  sprint de merges   permiso de época 5 -> NO vale. Hace falta una firma tuya nueva.
  workers            sin permiso propio -> pueden seguir
  Yema               sin permiso propio -> pueden seguir

Qué no puedo reanudar yo:
  sprint de merges   su parada propia solo la levanta un permiso nuevo tuyo
  Soul               su parada solo la levantas tú: "soul resume"
  Yema               su reactivación exige persona en terminal

Estado: REANUDACIÓN INCOMPLETA — faltan 3 pasos tuyos.
```

Puntos que ves aquí en llano:

- Savia **no se salta** las paradas propias de cada ejecutor: te dice cuáles te tocan a ti.
- Si queda un efecto dudoso sin aceptar por ti, `resume` **no procede** y lo lista.
- Reanudar no devuelve a la vida permisos anteriores a una revocación.

---

## Lo que este prototipo NO enseña

- No deshace lo irreversible.
- Un agente puede parar, pero no reanudar.
- Parar a un ejecutor concreto sin parar al resto (`quarantine`) queda para S1; aquí solo se simula la parada global.
- No hay todavía ninguna orden real: todo esto es una simulación para que decidas si es lo que querías.
