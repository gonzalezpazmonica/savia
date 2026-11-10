# SE-512 — Prototipo S0: el permiso nocturno, visto desde el móvil

> **Todo lo que sigue son datos de ejemplo.** Números de PR, horas, ids, hashes y títulos son inventados para enseñar la forma. Nada de esto está aprobado ni se ha ejecutado. Se lee en el móvil, de arriba abajo: tres pantallas.

Escenas de la spec a las que corresponde cada pantalla: la 1 (el permiso), la 5 (el resumen de la mañana) y la 4 (el parón ante una regresión).

---

## Pantalla 1 — La PR de permiso, en la app de GitHub

Llega como notificación a las 22:40 (EJEMPLO). Repo: el de aprobaciones. La abre quien ha pedido el sprint nocturno (la App de los agentes); la fusiona solo la operadora.

**Título**

> Permiso nocturno de Savia: fusionar PR de documentación y changelog hasta las 08:00

**Descripción** (la escribe el lado de los agentes; no es la defensa, lo que vale es el fichero)

> **Qué apruebas.** Que esta noche Savia fusione sola, de una en una, las PR del repo `savia` que cumplan **todo** esto en el momento de fusionarlas:
>
> - Solo tocan `docs/**` o `CHANGELOG.d/**`, y nada de lo que está en la lista de «queda fuera».
> - Son de riesgo bajo (niveles 1 o 2). El nivel 3 o 4 nunca se fusiona con este permiso.
> - Dos revisoras distintas las han aprobado sobre la versión exacta que se va a fusionar, y ninguna es la autora.
> - La comprobación automática de la PR está en verde, y `main` también lo está justo antes y justo después.
>
> **Límites.** Desde que fusiones esta PR hasta las 08:00 (EJEMPLO: 9 h 20 min si la fusionas a las 22:40). Máximo 12 fusiones. Si dos PR seguidas se aparcan porque cambian mientras se fusionan, se para todo.
>
> **Si una revisora pidió cambios** (HOLD), la PR solo entra cuando esa misma revisora y otra la aprueban sobre la versión arreglada. Máximo cuatro revisiones por PR en la noche.
>
> **Queda fuera siempre** (la lista completa derivada está en el fichero): reglas de gobernanza y de seguridad, `.claude/settings*.json`, `.opencode/`, `.github/workflows/`, hooks, definiciones de las revisoras, scripts de confidencialidad y de validación, dependencias, y todo script que ejecute un workflow.
>
> **Cómo se para.** Poniendo la etiqueta `savia-stop` a cualquier issue o PR del repo, o con el parón automático de más abajo. No se amplía: para otra noche, otra PR como esta.
>
> **Qué NO te pide esta noche:** nada más. No habrá más avisos de permiso ni preguntas hasta las 08:00. Lo que necesitaría una respuesta tuya te espera en la cola de la mañana.
>
> `Digest de la política: 3f9a0c…e71b` (EJEMPLO)

**Pestaña «Files changed»** — exactamente un fichero añadido (si hay más, el verificador no lo acepta):

```
+ aprobaciones/savia-politica/20261110-noche-7c41-a9d03e5f.json
```

```json
{
  "schema": "aprobacion/1",
  "tipo": "savia-politica",
  "nonce": "0b6e51c8d2a47f39",
  "emitida": "2026-11-10T21:40:00Z",
  "caduca": "2026-11-11T07:00:00Z",
  "objeto": {
    "kind": "policy",
    "id": "7c41e90b2d5a8f13",
    "not_before": "2026-11-10T21:40:00Z",
    "not_after": "2026-11-11T07:00:00Z",
    "repos": [
      {
        "repo": "savia",
        "base": "main",
        "include": ["docs/**", "CHANGELOG.d/**"],
        "exclude": []
      }
    ],
    "tiers": [1, 2],
    "max_merges": 12,
    "max_parks_in_row": 2,
    "universe": "open",
    "reviewers": ["revisora-a", "revisora-b", "revisora-c"],
    "max_reviews_per_pr": 4,
    "main_pending_timeout": 20,
    "required_checks": ["(EJEMPLO) los de la protección viva de la rama"]
  },
  "resumen": "(EJEMPLO) Fusionar solas, hasta las 08:00 (hora local), como máximo 12 PR del repo savia que solo toquen docs/** o CHANGELOG.d/**, de riesgo 1 o 2, con dos revisoras distintas de acuerdo sobre la versión exacta, la comprobación de la PR en verde y main en verde antes y después. Queda fuera lo de gobernanza, hooks, workflows y lo que estos ejecutan."
}
```

Nota para quien lo lea: el `resumen` no lo escribe una persona. Se genera del `objeto` y el verificador lo regenera; si no coincide letra por letra, la aprobación no vale. Los hashes de código congelado (ejecutor, clasificador) también van en el `objeto`; aquí se omiten para que quepa en la pantalla.

**Lo que haces:** «Merge pull request» → «Confirmar». Tres toques desde la notificación. Después, a dormir.

**Lo que ocurre si no la fusionas:** nada. Sin la fusión no hay permiso, y el sprint no fusiona nada: lo deja todo en la cola de la mañana.

**Lo que ocurre si la fusionas tarde:** la ventana empieza cuando fusionas y termina a la hora escrita. Fusionada después de las 08:00, no vale.

---

## Pantalla 2 — El resumen de la mañana

Aparece en la cola de la app a las 08:05 (EJEMPLO), como una petición más de las que esperan algo de ti.

> **Noche del 10 al 11 — resumen del sprint nocturno** (datos de ejemplo)
>
> Ventana efectiva: 22:42 – 08:00 (hora local). El sprint se paró a las 04:31: `main` en rojo tras una fusión.
>
> **Fusionadas: 5 de 12 posibles**
>
> | PR | Título (ejemplo) | Nivel | Fusionada | Revisoras |
> |---|---|---|---|---|
> | #9101 | docs: aclara el flujo de aprobaciones | 1 | 23:10 | a, b |
> | #9102 | docs(changelog): fragmento de la semana | 1 | 00:02 | a, c |
> | #9103 | docs: corrige tabla de límites (tras un HOLD de a) | 1 | 03:08 | a, b |
> | #9104 | docs: índice de specs | 2 | 03:40 | b, c |
> | #9105 | docs: renombra guía de operación | 2 | 04:29 | a, b |
>
> **Paradas: 3**
>
> | PR | Por qué | Qué te toca |
> |---|---|---|
> | #9108 | Riesgo nivel 3. Este permiso nunca fusiona nivel 3. | Verla y fusionarla tú, o dejarla. |
> | #9109 | Toca `.claude/hooks/x.sh`, que está fuera del permiso. | Verla y fusionarla tú. |
> | #9110 | Una revisora dio HOLD sobre la versión actual. | Esperar el arreglo; no necesita nada de ti. |
>
> **No tocadas por el parón: 2** (#9106, #9107). Cumplían la regla; se evaluarán con el próximo permiso.
>
> **Motivo del parón:** `main` en rojo (`main_fail`) a las 04:31, dos minutos después de fusionar #9105. No se ha revertido nada. Detalle: el aviso de la pantalla 3.
>
> **Comprobación del registro:** íntegro. Cada fusión tiene guardadas las dos revisiones, la comprobación de la PR y la de `main`.
>
> **Esperan algo de ti (cola de la mañana):**
>
> 1. **Mirar `main`.** Está en rojo desde las 04:31. Probablemente por #9105 (la última fusionada), sin confirmar. [Ver el fallo] [Proponer revertir #9105 — lo haces tú]
> 2. **Reanudar.** Un parón no se levanta solo ni quitando la etiqueta: hace falta otra PR de aprobación como la de anoche. [Abrir la PR de permiso] (solo después de arreglar `main`)
> 3. **#9108 y #9109.** Fuera de este permiso por diseño. [Ver #9108] [Ver #9109]

---

## Pantalla 3 — El aviso de parón ante una regresión

Entra en la cola a las 04:31 (EJEMPLO). **Es pasivo: no suena ni vibra.** La propuesta es esperar a la mañana porque, con el sprint parado, no se fusiona nada más y no se pierde nada por no despertarte. (Esto está por confirmar: ver «Qué queda por decidir» en la spec.)

> **Parón del sprint nocturno** · 04:31 (ejemplo)
>
> **Qué ha pasado.** Tras fusionar #9105 a las 04:29, la comprobación de `main` ha terminado en rojo (`main_fail`). El sprint se ha parado.
>
> **Qué se ha hecho.** Nada más. No se ha revertido #9105, no se ha tocado ninguna otra PR y no se fusionará nada hasta que apruebes un permiso nuevo.
>
> **Qué no se sabe.** Si el fallo lo causó #9105 o es externo (infra de GitHub, un runner). El sprint no lo distingue y por eso no reintenta: fusionar sobre un `main` roto es peor que perder la noche.
>
> **Qué te toca, sin prisa:**
>
> - [Ver el fallo de `main`]
> - [Proponer revertir #9105] — la PR de reversión la abre un agente; la fusionas tú.
> - Cuando `main` esté en verde: [Abrir la PR de permiso] para reanudar.
>
> **Coste de esperar:** 2 PR elegibles (#9106, #9107) sin fusionar hasta que reanudes. Ninguna otra consecuencia.

---

## Lo que este prototipo NO muestra

- No muestra el hilo del guard nocturno ni lo que ve un agente cuando se le niega algo (va a la cola, con la orden lista).
- No muestra el informe completo (`report --policy`): esto es su resumen.
- No muestra cómo se instala la App ni el repo de aprobaciones (eso es SE-488).
- Los botones entre corchetes son los de la app de SE-504 sobre la cola de SE-514; aquí son texto.
