# SE-510 — Prototipo: lo que verías cuando una guarda bloquea

> **Esto es un prototipo para que lo confirmes o lo rechaces. Nada de esto está construido.**
> - «Antes» son los mensajes reales que dan hoy las guardas (leídos del código).
> - «Después» son textos **propuestos**; la orden `scripts/guard-blocks.sh` **no existe hasta S1**. Su salida de abajo está **simulada**.
> - El registro de la semana es un **ejemplo inventado**. No hay ningún dato real.

Qué es una *guarda*: un pequeño control automático que mira cada orden antes de ejecutarla y puede pararla. Un *bloqueo falso* es cuando para una orden que era legítima.

Cada bloqueo llevará una etiqueta al principio del mensaje:

- **[FORMA]** — la guarda no entendió cómo está escrita la orden. La orden en sí era legítima. El mensaje te dice cómo escribirla de otra manera y la guarda queda registrada para arreglarla.
- **[POLÍTICA]** — la guarda para algo que no se debe hacer sin tu permiso (borrar, forzar un envío, tocar `main`, un secreto). El mensaje no sugiere rodeos: te lo manda a ti.
- Si no está claro, se trata como POLÍTICA.

---

## Escena 1 — 23:40, una worker abre su carpeta de trabajo

Orden: `git worktree add -q -b agent/ejemplo-1 /tmp/ejemplo origin/main`

**Hoy**

```
BLOQUEADO: destino de git add no reconocido con certeza (fail-closed). Forma admitida: git -C <ruta> add …
```

La orden no contiene ningún `git add`. La guarda se equivoca de texto. Quien la lee solo ve que «algo» fue bloqueado y no sabe que la culpa es de la guarda.

**Después (propuesto)**

La orden pasa. No hay mensaje.

Si otra orden legítima vuelve a confundir a una guarda, sale esto:

```
[FORMA] BLOQUEADO por validate-bash-global: no he sabido leer a dónde apunta esta orden.
  La orden en sí no parece peligrosa. Escríbela así: git -C <ruta> worktree add …
  Queda registrado como bloqueo nº 31 con la orden exacta. Si era legítima, márcalo:
  bash scripts/guard-blocks.sh mark 31 false-positive
```

Y lo que NO cambia: un `git add -A` de verdad metido en un script sigue bloqueándose.

```
[POLÍTICA] BLOQUEADO por validate-bash-global: orden que añade ficheros a git sin destino claro.
  Esto no es un fallo de formato: no la ejecuto. Decide tú.
```

---

## Escena 2 — resuelves un conflicto con `git checkout --merge -- fichero`

Estado: tienes cambios sin guardar en otro fichero.

**Hoy**

```
BLOQUEADO: Cambio de rama con cambios sin commitear.

  Repo: /ruta/del/repo
  Ficheros modificados: 1
  Ficheros sin rastrear: 0

  Opciones:
    1. git add + git commit (recomendado)
    2. git stash -u (temporal)

  NUNCA cambiar de rama sin guardar los cambios.
```

No estás cambiando de rama; estás recuperando un fichero. El mensaje te contesta a otra pregunta.

**Después (propuesto)**

`git checkout --merge -- fichero.txt` pasa. No hay mensaje.

Y esto sigue igual, ahora con etiqueta:

```
[POLÍTICA] BLOQUEADO por block-branch-switch-dirty: cambio de rama con cambios sin guardar.
  Repo: /ruta/del/repo · modificados: 1 · sin rastrear: 0
  Guárdalos antes (commit) o aparca con git stash -u. No cambio de rama con trabajo sin guardar.
```

(`git checkout main` con el árbol sucio.)

---

## Escena 3 — abres una PR desde una carpeta de trabajo

Orden: `gh pr create --draft …`, ejecutada en la carpeta de trabajo que tiene su propio `.pr-summary.md` de hace 5 minutos.

**Hoy**

```
BLOQUEADO: .pr-summary.md tiene 97h de antiguedad (max 24h).
  Actualizalo para reflejar los cambios de este PR.
```

Mira el resumen de otra carpeta (la principal), no el de la carpeta donde ejecutas la orden. Tu resumen fresco no cuenta.

**Después (propuesto)**

La orden pasa: se mira el resumen de la carpeta donde ejecutas `gh`.

Al crear el fichero ya sabes qué lleva (plantilla que entrega `pr-plan`):

```
## Qué hace este PR (en lenguaje no técnico)

Un párrafo en lenguaje llano: qué cambia, para quién y qué no cambia.
```

Y si falta el encabezado exigido, sigue bloqueando, pero con la etiqueta y el texto literal a mano:

```
[FORMA] BLOQUEADO por pr-summary-gate: a .pr-summary.md le falta el encabezado obligatorio.
  Añade exactamente esta línea:
  ## Qué hace este PR (en lenguaje no técnico)
```

Si el resumen de tu carpeta es viejo o no existe, también bloquea, con su etiqueta:

```
[POLÍTICA] BLOQUEADO por pr-summary-gate: .pr-summary.md de esta carpeta tiene 97 h (máximo 24 h).
  Reescríbelo para esta PR. No abro la PR con un resumen de otro trabajo.
```

---

## Escena 4 — el lunes miras cuántos bloqueos hubo

**Simulado: la orden no existe hasta S1.** Registro de ejemplo de una semana (inventado).

```
$ bash scripts/guard-blocks.sh report --since 7d
Semana 2026-W99 (EJEMPLO, datos inventados)

guarda                      bloqueos  etiquetados  falsos  tasa falsos  sin etiquetar
validate-bash-global              9            6       2        33 %              3
block-branch-switch-dirty         5            5       1        20 %              0
pr-summary-gate                   7            3       3       100 %              4
repeat-tool-guard                 2            0       0      UNKNOWN              2
block-force-push                  1            1       0         0 %              0
TOTAL                            24           15       6        40 %              9

Una tasa UNKNOWN significa «sin etiquetas todavía», nunca 0 %.
Falsos sin entrar en el corpus de órdenes legítimas: 6 (cada uno necesita su par peligroso).
```

Ver cada uno:

```
$ bash scripts/guard-blocks.sh list --since 7d --guard pr-summary-gate
 id  hora         clase     motivo                                      etiqueta
 18  lun 09:12    POLÍTICA  .pr-summary.md de esta carpeta tiene 97 h   falso
 19  lun 09:14    POLÍTICA  .pr-summary.md de esta carpeta tiene 97 h   falso
 27  mié 17:40    FORMA     falta el encabezado obligatorio             verdadero
 (la orden no se guarda por defecto; solo una huella con clave local)
```

---

## Escena 5 — el despachador de un evento casca

El despachador es la pieza que decidiría, en un solo sitio, qué guardas corren antes de cada herramienta.

**Hoy** (el despachador existe pero no está en uso): si su tabla falta, la orden pasa y el aviso queda en un registro que nadie mira.

```
[dispatch-pretooluse] WARNING: routing file not found: …/routing-pretooluse.tsv
(la herramienta se ejecuta igualmente)
```

**Después (propuesto)**: la herramienta NO se ejecuta.

```
[POLÍTICA] BLOQUEADO por el despachador: no ha podido comprobar esta orden.
  Qué falló: falta la tabla de guardas (routing-pretooluse.tsv).
  No dejo pasar nada que no haya revisado. La orden no se ha ejecutado.
  Queda registrado como bloqueo nº 32.
```

Otros fallos con la misma regla, cada uno con su motivo:

```
[POLÍTICA] BLOQUEADO por el despachador: la guarda pr-summary-gate no terminó en 5 s.
[POLÍTICA] BLOQUEADO por el despachador: la guarda block-force-push no existe en el disco.
[POLÍTICA] BLOQUEADO por el despachador: la entrada de la herramienta no es un JSON válido.
```

Un despachador roto bloquea todo al principio. Por eso el plan lo prueba una semana en paralelo, sin mandar, antes de sustituir nada.

---

## Qué tienes que decidir mañana

1. ¿Las etiquetas FORMA / POLÍTICA y los textos de «Después» te sirven para saber qué hacer en cada bloqueo?
2. ¿El informe de la escena 4 te dice lo que querías saber un lunes?
3. ¿Aceptas que, si no está claro, un bloqueo se trate como POLÍTICA (pararte y preguntarte)?
