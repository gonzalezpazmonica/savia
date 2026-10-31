# Gramática de órdenes estructuradas

La app envía `POST /api/v1/soul/ordenes {"orden": "<texto>"}`. Soul la interpreta con una
gramática determinista: **sin modelo, sin heurísticas, sin aproximar**. Los botones de la
app llaman directamente a los endpoints REST; las órdenes existen para el campo de
«orden corta» y para atajos. Una orden es siempre equivalente a un endpoint (columna
«Equivale a»).

## Reglas léxicas

- Se pasa a minúsculas, se quitan acentos y se parte por espacios en blanco. Máximo 200 caracteres.
- Primer término = verbo. El resto son argumentos posicionales o `clave:valor`.
- `ID` = identificador opaco `[A-Za-z0-9_.-]{1,64}` (lo da la propia API; nunca un nombre de persona).
- `FECHA` = `AAAA-MM-DD` o `AAAA-MM-DDThh:mm:ssZ` (UTC). `HORA` = `hh:mm` (UTC).
- `DURACION` = entero + `m` o `h` (`90m`, `2h`), máximo 7 días (`168h`).

## EBNF

```
orden      = consulta | porque | correccion | atencion | avisos | detalle | info ;

consulta   = ( "q1" | "abierto" | "q2" | "depende" | "q3" | "cambio" | "q4" | "compromisos" ) , { filtro } ;
filtro     = "proyecto:" ID | "persona:" ID | "desde:" FECHA | "hasta:" FECHA ;
porque     = "porque" , ID ;
correccion = ( "resuelto" | "no-aplica" | "mio" | "no-mio" ) , ID ;
atencion   = "modo" , ( "disponible" | ( "foco" | "descanso" | "fuera" ) , ( "durante:" DURACION | "hasta:" FECHA ) ) ;
avisos     = "resumen" , ( "inicio" | "cierre" ) , ( HORA | "off" )
           | "presupuesto" , N , "/" , N , ( "m" | "h" )       (* máx. avisos / ventana *)
           | "tope-alertas" , N
           | "aviso" , ( "on" | "off" ) , TIPO_AVISO ;
detalle    = "detalle" , ( "completo" | "titulos" | "recuentos" ) ;
info       = "adaptadores" | "estado" | "ayuda" | "?" ;
TIPO_AVISO = "reunion_proxima" | "vencimiento" | "documento_sin_leer" | "espera_respuesta" ;
```

Reglas semánticas:

- `q3` / `cambio` **exige** `desde:`. Sin él es `argumento_invalido`, no se supone «ayer».
- `desde:` y `hasta:` en `q1`/`q2` no se admiten (`argumento_invalido`). En `q4` acotan el vencimiento.
- Filtros repetidos o desconocidos son `argumento_invalido`. Un `ID` que no existe da la misma
  respuesta que uno ajeno: 404 `NOT_FOUND`.
- `atencion` con `foco`/`descanso`/`fuera` exige ventana; `disponible` no la admite.
- `detalle` solo hasta el máximo de la instalación (422 `LEVEL_NOT_ALLOWED`).
- Crear o cambiar una regla de alerta no tiene orden: exige el formulario de la app
  (`PUT /avisos`), porque una alerta es una decisión del operador y no un atajo de texto.

## Equivalencias

| Orden | Equivale a | `accion` |
|---|---|---|
| `q1 proyecto:p-1` | `GET /q/q1?proyecto=p-1` | `consulta` |
| `q3 desde:2026-10-30` | `GET /q/q3?desde=2026-10-30T00:00:00Z` | `consulta` |
| `porque e-12` | `GET /elementos/e-12/porque` | `porque` |
| `resuelto e-12` | `POST /elementos/e-12/correccion {"tipo":"resuelto"}` | `correccion` |
| `modo foco durante:2h` | `PUT /atencion {"modo":"FOCO","hasta":<ahora+2h>}` | `atencion` |
| `modo disponible` | `PUT /atencion {"modo":"DISPONIBLE"}` | `atencion` |
| `resumen inicio 07:30` | `PUT /avisos` con `resumen_inicio` | `avisos` |
| `aviso off vencimiento` | `PUT /avisos` sin ese tipo | `avisos` |
| `detalle recuentos` | `PUT /detalle {"nivel":"recuentos"}` | `detalle` |
| `adaptadores`, `estado`, `ayuda` | `GET /adaptadores`, `/estado`, lista de órdenes | igual |

## Ejemplos

Válidas (todas devuelven `interpretada: true` y en `resultado` el mismo cuerpo que el endpoint):

```
q1
abierto proyecto:p-alfa
q2 persona:per-3
q3 desde:2026-10-30
q4 hasta:2026-11-07
porque e-12
no-aplica e-9
modo descanso hasta:2026-10-31T21:00:00Z
resumen cierre off
presupuesto 5/2h
tope-alertas 3
detalle titulos
```

Texto libre u orden que no casa (siempre HTTP 200, `interpretada: false`; **no se guarda, no
se registra y no se envía a ningún modelo ni a ninguna parte**):

```json
POST /ordenes {"orden": "¿qué tengo pendiente con Marta esta semana?"}
→ 200 {"interpretada": false, "motivo": "texto_libre",
       "mensaje": "No puedo interpretar texto libre aquí; usa una de estas órdenes.",
       "ordenes": [{"forma": "q1 [proyecto:ID] [persona:ID]", "ejemplo": "q1"}, ...]}
```

Orden con verbo conocido y argumentos malos (`q3` sin `desde:`, `modo foco` sin ventana):

```json
POST /ordenes {"orden": "q3"}
→ 200 {"interpretada": false, "motivo": "argumento_invalido",
       "mensaje": "No puedo interpretar texto libre aquí; usa una de estas órdenes.", "ordenes": [...]}
```

La respuesta nunca repite el texto recibido (podría llevar contenido de un tercero pegado por
error) y nunca dice «he entendido»: o ejecuta una orden de la gramática o dice que no puede.

## Texto libre en el futuro

`GET /estado` expone `texto_libre`: `desactivado` (por defecto, el único valor de v1),
`modelo_local` o `proveedor_aprobado`. Si una instalación lo activa, esa rama es otra
spec; el contrato ya reserva el campo y la app muestra su campo de texto libre solo si
no es `desactivado`.
