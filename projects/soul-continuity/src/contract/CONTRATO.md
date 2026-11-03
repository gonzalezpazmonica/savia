# Contrato del banco de continuidad (SE-490, AC-2/AC-3)

Este documento fija la semántica con la que se escribió la verdad de los escenarios **antes de ejecutar nada**. Una implementación que siga este contrato y los tipos de `src/claims.ts` y `src/adapter.ts` se puede medir con el runner sin cambiarlo.

Todos los instantes van en UTC. «Hoy» es el día UTC de `now`.

## 1. Claves

`<adaptador>:<tipo>:<ref>`; `ref` es el identificador nativo de la fuente y no contiene `:`.

| Afirmación | Clave |
|---|---|
| Reunión (M365) | `m365-calendar:meeting:<eventId>` |
| Reunión (Google) | `google-workspace:meeting:<eventId>` |
| Hilo esperando mi respuesta | `m365-mail:awaiting_reply:<conversationId>@<id del último mensaje entrante>` · `google-workspace:awaiting_reply:<threadId>@<messageId>` |
| Correo marcado con fecha | `m365-mail:dated_commitment:<messageId>` |
| Mención en chat | `m365-teams:mention:<messageId>` |
| Mención en GitHub | `github:mention:<repo>#<n>` |
| Documento con comentarios | `m365-files:document_comments:<itemId>` · `google-workspace:document_comments:<fileId>` |
| Tarea asignada | `jira:task_assigned:<issueKey>` · `azure-devops:task_assigned:<id>` · `github:task_assigned:<repo>#<n>` · `web:task_assigned:<site>~<itemId>` |
| Revisión pedida | `azure-devops:review_request:<repo>!<prId>` · `github:review_request:<repo>#<n>` |
| Compromiso con fecha en web | `web:dated_commitment:<site>~<itemId>` |
| Cambio de página web | `web:web_page_change:<site>~<pageId>` |

El último mensaje entrante forma parte de la clave del hilo: si llega un mensaje nuevo después de que el operador marcara el hilo como resuelto, es un hecho nuevo con clave nueva. La clave revocada no vuelve.

## 2. Cómo se forma cada afirmación

- **Reunión.** Evento del calendario propio (`/me`, `primary`) no cancelado, con inicio en [now − 1 d, now + 14 d]. `due_at` = inicio. `open` = no declinada por el operador. Los calendarios delegados o de otras personas no se leen.
- **Esperando mi respuesta** (regla de la spec, solo metadatos). Por hilo:
  1. el último mensaje del hilo (entrada y enviados juntos, por fecha) no es mío;
  2. alguna de mis direcciones está en `To` de ese último mensaje (CC no cuenta, una lista de distribución tampoco);
  3. no hay ningún mensaje mío en enviados del mismo buzón posterior a ese mensaje.
  Un reenvío mío dentro del mismo `conversationId` cuenta como mensaje mío (la regla es de metadatos; limitación documentada). Un mensaje mío a mí mismo no crea espera. `awaiting_operator = open = true`.
- **Correo marcado con fecha.** Mensaje de la bandeja de entrada con `flag.flagStatus = flagged` y `flag.dueDateTime`. `due_at` = vencimiento.
- **Mención en chat.** Mensaje de chat de los últimos 7 días que me menciona y tras el cual no hay ningún mensaje mío en ese chat. `awaiting_operator = true`.
- **Mención en GitHub.** Incidencia o PR abierta que me menciona (`mentions:@me is:open`), salvo que también esté asignada a mí o tenga revisión pedida a mí.
- **Documento con comentarios.** Documento compartido conmigo con ≥ 1 comentario sin resolver. `awaiting_operator = false`.
- **Tarea asignada.** Asignada a mi identidad y no terminada. `due_at` = vencimiento si lo hay. `awaiting_operator = true`.
- **Revisión pedida.** PR activa con revisión pedida a mí sin voto emitido. `awaiting_operator = true`.
- **Ruta web.** Las recetas devuelven filas con `kind` (`task`, `deadline`, `page`). `page` es un cambio de página sin receta: `open = false`, `event_at` = última modificación.

Todo lo que leen los adaptadores de oficina es N4. GitHub es N2 por defecto. La configuración puede subir el nivel, nunca bajarlo.

`event_at` es la fecha del último mensaje entrante (hilos), de la mención, del último comentario sin resolver (documentos) o de la última modificación (páginas web); en el resto de tipos es `null`.

`attrs` lleva solo metadatos escalares. Para el correo: `last_from` (dirección) y `sender_auth` (`tenant`, `dkim_dmarc`, `unauthenticated`, `unknown`). **Nunca cuerpos.**

### Identidad del remitente (AC-4c)

- Ruta Graph: `tenant` si la cabecera `X-MS-Exchange-Organization-AuthAs` vale `Internal` y el dominio de `From` es el del inquilino; si no, `dkim_dmarc` si `Authentication-Results` dice `dkim=pass` y `dmarc=pass` con `header.from` igual al dominio de `From`; si no, `unauthenticated`. Sin cabeceras (solo `Mail.ReadBasic`), `unknown`.
- Ruta Google: igual con `Authentication-Results`.
- Ruta web: siempre `unknown`.

## 3. Estados de adaptador

Ver `ADAPTER_STATUS` en `src/adapter.ts`. En concreto:

- Sin entrada en la configuración: `not_configured`.
- Consentimiento con `revoked_at` ≤ `now`: `consent_revoked`.
- El almacén de credenciales responde `admin_consent_required` en la ruta Graph: `admin_consent_required`, `fallback = "web"`. Nunca se piden permisos de más ni se usan identificadores ajenos.
- 401 de la API: `token_expired` («vuelve a iniciar sesión»).
- Ruta web con sesión caducada: `session_expired`.

Un adaptador que falla no aporta nada (fail-closed) y lo dice en `adapters` de la respuesta.

## 4. Preguntas

Solo cuentan afirmaciones **utilizables** (`DECLARED`, `OBSERVED`, `CONFIRMED`) con sensibilidad ≤ `max_level`. Las que superan `max_level` no salen: se suman en `withheld`.

| Pregunta | Entra |
|---|---|
| **Q1** | `meeting` abierta con inicio en [00:00 de hoy, 00:00 de pasado mañana); `task_assigned`, `review_request` y `awaiting_reply` abiertas; `document_comments` |
| **Q2** | afirmaciones abiertas con `awaiting_operator`: `awaiting_reply`, `mention`, `task_assigned`, `review_request` |
| **Q3** | diferencia entre `previous` y la actual del mismo operador: claves utilizables nuevas (`added`), que dejaron de serlo (`removed`) o con otra huella (`changed`, ver `fingerprint`). No se informan como `removed` las claves revocadas o sustituidas en el libro ni las de un adaptador que no respondió en la actual. Si `previous` es de otro operador, se rechaza (excepción). |
| **Q4** | afirmaciones abiertas con `due_at` en [now − 7 d, now + 14 d] de tipo `task_assigned`, `dated_commitment` y `review_request`, y `meeting` abiertas con inicio en [now, now + 14 d] |
| **ALERT** | sobre `awaiting_reply` utilizables cuyo `last_from` está en una regla: **alerta** si `sender_auth` es `tenant` o `dkim_dmarc`; **aviso** si la ruta es `web` (nunca alerta); nada si es `unauthenticated` o `unknown` en ruta API |

Filtros: `types`, `adapters` y `ref_prefix` (prefijo del `ref` nativo).

### Niveles de detalle

- `completo`: elementos con `title` y `attrs`.
- `titulos` (por defecto): elementos con `title`, sin `attrs`.
- `recuentos`: sin elementos; solo `counts` por tipo y `withheld`.

## 5. Correcciones e instalación

- `answer` sobre una instantánea caducada (`expires_at` ≤ `now`) se rechaza (excepción).

- `correct` anota en el libro **del operador activo**. El estado de una instalación es común a sus perfiles, pero cada operador solo ve su libro y su caché.
- `snapshot` aplica el libro en cada reconstrucción: lo revocado no vuelve aunque la fuente lo repita.
- Nada de lo que escribe la implementación en `stateDir` puede contener cuerpos de mensajes ni tokens.

## Emparejamiento directo app ↔ Soul (`soul-pair-v2`)

La app se conecta en **modo Space** (a través del servidor de escritorio de Space) o en **modo directo** (al núcleo de Soul en el portátil, por la VPN). En modo directo:

1. `soul pair` abre una ventana de 10 minutos y muestra IP, puerto, una **clave de emparejamiento** de un solo uso al estilo de las API key, `soulpk_<30 base62>_<6 base62>` (178 bits de un CSPRNG; el sufijo es el CRC32 de la parte aleatoria y solo detecta errores de copia), la **huella corta** del certificado (16 primeros hex de SHA-256(SPKI), en grupos de 4) y un **QR** con `soul://pair?v=2&h=<ip>&p=<puerto>&k=<clave>&f=<huella corta sin espacios>`. La clave es sensible a mayúsculas: solo se quitan los espacios en blanco de los extremos. La app valida formato y checksum antes de enviar nada.
2. `POST /v1/pair/challenge` `{version: "soul-pair-v2", client_nonce}` → `{server_nonce, spki_sha256, proof}` con `proof = HMAC-SHA256(clave, "soul-pair-v2|server|" + client_nonce + "|" + server_nonce + "|" + spki_sha256)`. La app compara `spki_sha256` con el certificado que ve y verifica `proof` con la clave pegada o leída del QR; si algo no casa, aborta. La clave nunca viaja.
3. `POST /v1/pair/complete` `{server_nonce, device_name, device_jwk, proof}` con `proof = HMAC-SHA256(clave, "soul-pair-v2|client|" + client_nonce + "|" + server_nonce + "|" + jwk_thumbprint)`. Soul registra el dispositivo **ya ligado a esa clave** y devuelve `{device_id, token, expires_at}`. Las peticiones siguientes llevan el token y la prueba DPoP con esa clave.
4. La app fija `sha256/<base64 SPKI>` del certificado hoja autofirmado (`CA:false`). Si el certificado se renueva, hay que volver a emparejar.

Nonces, HMAC y huellas en base64url sin relleno. Errores con el sobre de la API: `PAIR_EXPIRED` 410 (sin ventana, caducada o usada), `PAIR_BAD_PROOF` 401, `PAIR_LOCKED` 423 (tras 3 pruebas fallidas), `PAIR_RATE` 429 (más de 10 retos por ventana), `PAIR_VERSION` 426 (reto sin `version` o con otra: cliente soul-pair-v1, retirado; el mensaje pide actualizar la app) e `INVALID_INPUT` 400. Esquemas en `openapi.json` (`x-emparejamiento-directo`). Los vectores fijos están en `vectores-emparejamiento.json`; la app copia ese fichero tal cual y el núcleo lo comprueba en `test/pairing.test.ts`.
