# Adaptadores de API de Soul Continuidad v1 (SE-490)

Conectores de solo lectura que cumplen el contrato `SourceAdapter` de `../contract/adapter.ts`, sin cambiarlo. Hablan con cada fuente solo a través de `Transport` y `CredentialStore`. Nunca persisten cuerpos de mensaje, ni descripciones, ni comentarios.

El adaptador `web` (navegador en un perfil dedicado, con recetas) y la ruta web de Microsoft 365 son otra pieza de SE-490. Este directorio no los incluye.

## Qué lee cada adaptador

| Adaptador | Permisos delegados | Qué lee | Qué devuelve |
|---|---|---|---|
| `m365-mail` | `Mail.Read` (o `Mail.ReadBasic` con `sender_identity: false`) | Metadatos de la bandeja de entrada y de enviados del propio buzón | `awaiting_reply` según la regla de la spec y `dated_commitment` para correos marcados |
| `m365-calendar` | `Calendars.ReadBasic` | `calendarView` del calendario propio, de ayer a 14 días, en UTC | `meeting` |
| `m365-teams` | `Chat.Read` + `User.Read` | Mensajes de los chats del operador en los últimos 7 días | `mention` sin respuesta posterior del operador |
| `m365-files` | `Files.Read.All` | `sharedWithMe` y sus comentarios | `document_comments` sin resolver |
| `google-workspace` | `gmail.metadata`, `calendar.readonly`, `drive.readonly` y, opcional, `tasks.readonly` | Cabeceras de Gmail, calendario `primary`, Drive compartido y Tasks | `awaiting_reply`, `meeting`, `document_comments` y `dated_commitment` |
| `jira` | `read:jira-work` | JQL `assignee = currentUser() AND statusCategory != Done` | `task_assigned` |
| `azure-devops` | `vso.work`, `vso.code` | WIQL `@Me` en estado abierto; PR activas con revisión pedida | `task_assigned`, `review_request` |
| `github` | `repo:read` (etiqueta lógica, ver abajo) | Búsqueda de revisiones pedidas, asignaciones y menciones | `review_request`, `task_assigned`, `mention` |

`repo:read` no es un scope OAuth de GitHub: es la etiqueta con la que se guarda la credencial. Con una app OAuth clásica, leer incidencias privadas exige `repo`, que incluye escritura, así que el mínimo privilegio no se cumple por esa vía. Hay que usar una GitHub App o un PAT de grano fino con Issues y Pull requests en solo lectura. El adaptador nunca escribe (`HttpTransport` solo deja salir GET), pero eso no limita lo que el token permitiría.

`Mail.Read` se pide solo porque las cabeceras de autenticación del remitente (`internetMessageHeaders`) no llegan con `Mail.ReadBasic`. Sin ellas no hay alertas por remitente autenticado (AC-4c). Con `sender_identity: false`, el remitente queda `unknown` y no se dispara ninguna alerta.

Cada adaptador declara en `descriptors.ts`:

- propósito;
- nivel: N4 para datos de empresa; GitHub, N2;
- TTL de sus afirmaciones;
- permisos;
- qué no guarda nunca;
- qué hace revocarlo.

## Garantías

- **Solo lectura.** `HttpTransport` deja salir GET y HEAD. Admite un POST solo si es una lectura de la lista cerrada `READ_POSTS`, que hoy contiene solo el WIQL de Azure DevOps. Cualquier otra petición se rechaza antes de salir.
- **Solo metadatos.** Las peticiones de Graph usan `$select` y Gmail se lee con `format=metadata`. Si la API devuelve cuerpos de todos modos, el adaptador los descarta campo a campo. Hay un test del banco que lo comprueba con una API que ignora `$select`.
- **«Esperando mi respuesta».** Se calcula solo con metadatos (`awaiting.ts`). El último mensaje del hilo no es del operador, el operador está en `To` (CC no cuenta) y no hay ningún enviado suyo posterior en el mismo buzón. Por eso cuenta una respuesta enviada desde cualquier cliente.
- **Remitente autenticado (AC-4c).** El remitente cuenta como autenticado si es del mismo inquilino (`X-MS-Exchange-Organization-AuthAs: Internal` y su dominio) o si pasa DKIM y DMARC con `header.from` igual al dominio de `From`. La cabecera `From` sola nunca basta. En M365 se puede configurar:
  - `params.tenant_domain`: dominio del inquilino. Si no se configura, se usa el de la primera identidad del operador.
  - `params.authserv_ids`: `authserv-id` aceptados. Hace falta si delante de Exchange Online hay una pasarela de terceros o un escenario híbrido; sin él, se usa la primera `Authentication-Results` sin comprobar su `authserv-id`, y si una pasarela no retira una cabecera falsificada que quede la primera, un correo externo podría contarse como autenticado. En Exchange Online conviene fijarlo siempre (el `authserv-id` del inquilino); el impacto se limita a la heurística de «esperando respuesta».

  Un valor inválido falla cerrado (`error`).
- **Paginación con tope.** Si una colección supera el tope de páginas, el adaptador falla cerrado (`unavailable`) y no entrega datos parciales. Para paginar, de un enlace `nextLink` o `Link` solo se usa la ruta: el token no puede salir hacia otro host.
- **Delta queries del correo (riesgo R3).** Funcionan con `FileDeltaCache`:
  - cada lectura tiene un tope de páginas;
  - si la ronda no termina, se guarda el enlace de continuación y el adaptador responde `unavailable` hasta completarla;
  - un `410` o un `syncStateNotFound` provoca una sola resincronización desde cero;
  - un cambio ilegible retira el elemento, en vez de conservar sus metadatos viejos.
- **Throttling.** `HttpTransport` respeta `Retry-After` en 429 y 503, con un máximo de reintentos y de espera. Si la espera pedida supera el tope, el adaptador queda `unavailable` hasta la siguiente lectura. Google señala la cuota con 403 `rateLimitExceeded`, y eso también se trata como `unavailable`.
- **Fail-closed por consentimiento.** Si el almacén o el proveedor de identidad dicen que el inquilino exige administración, el adaptador no llama a la API, responde `admin_consent_required` y ofrece `fallback: "web"`. Un 403 de Graph se interpreta igual.
- **Credenciales.**
  - `SystemCredentialStore` guarda los tokens solo en el almacén del sistema: Secret Service, Llavero o Credential Manager.
  - El secreto viaja por stdin y nunca en argv.
  - Hay una entrada por operador, servicio y permisos.
  - El transporte corta cualquier respuesta de más de 16 MiB (`maxBytes`) con error.
  - Si no hay almacén reconocido, el adaptador no se activa.
- **Autenticación.** Flujo de dispositivo (RFC 8628) o de navegador con PKCE y redirección a `127.0.0.1` (`oauth.ts`). Hay que usar un identificador de aplicación propio del operador o de su organización. `assertOwnClient` rechaza los de aplicaciones conocidas de Microsoft y Google, pero es una salvaguarda contra errores, no un control: la lista es incompleta por naturaleza y el propietario lo declara el operador.
- **Revocación (AC-5).** `revokeAdapter` borra primero la caché local del adaptador y después sus tokens, en todas las variantes de permisos. No toca otros adaptadores ni otros operadores. No invalida la concesión en el proveedor: el refresh token sigue vigente allí hasta que caduque o la persona retire el acceso de la aplicación desde su cuenta.

## Límites conocidos

- **Teams.** Graph identifica a las personas por su id de Entra, no por el correo. Si no llega `params.m365_user_id`, el adaptador lo pide con `GET /me` (por eso el permiso es `Chat.Read` + `User.Read`). Si tampoco puede leer `/me`, devuelve `error`: dar «ok» con cero menciones sería un falso verde. Los mensajes se piden en orden de creación (`$orderby=createdDateTime desc`).
- **Correo M365 sin ventana temporal.** El contrato no limita «esperando mi respuesta» en el tiempo, así que el delta inicial recorre todo el buzón por rondas. Sin `FileDeltaCache`, una carpeta con más de `maxPages × pageSize` mensajes queda `unavailable` en cada lectura. En producción hay que usar la caché.
- **Claves de GitHub.** La referencia es `<repo>#<n>`, como fija el contrato. Si dos propietarios tienen a la vez el mismo `repo#n`, el adaptador devuelve `unavailable` en lugar de fusionarlos; distinguirlos exige ampliar el contrato. Un 200 con `incomplete_results: true` también es `unavailable`, y lo mismo si lo recogido no llega a `total_count` (la búsqueda de GitHub no pasa de 1000 resultados). El permiso `repo:read` del descriptor es solo la clave de la entrada en el almacén: GitHub no tiene ese scope y no se pide al proveedor (el token se crea con acceso de lectura a los repositorios).
- **Renovación concurrente.** Dentro de un proceso, dos lecturas que necesitan renovar la misma entrada comparten una sola renovación. Entre procesos distintos no hay cerrojo: si dos instancias de Soul renuevan a la vez y el proveedor rota el refresh token, la segunda puede quedar `token_expired` y pedir un nuevo inicio de sesión. Soul corre una instancia por operador.
- **Marca de administración.** Cuando el proveedor dice que hace falta consentimiento de administración, la entrada queda marcada y no se vuelve a llamar a la red. La marca se quita con un nuevo inicio de sesión (`put`) o al revocar la fuente.
- **Caché delta del correo.** Al cargarla se validan los tipos de cada elemento y que no traiga campos de cuerpo; si no cumple, se descarta y se resincroniza. Guarda el resultado `sender_auth` ya calculado, no las cabeceras. Quien pueda escribir en el directorio de estado (0700, mismo usuario) podría marcar un remitente como autenticado. Ese mismo usuario ya puede modificar el código instalado o el almacén de credenciales, así que firmar la caché no añadiría una frontera real; se deja documentado.
- **Tamaño de la credencial.** En Windows, Credential Manager admite 2560 bytes por entrada y el JSON con los tokens de Entra suele pasar de 5 KB. Por eso el valor se guarda en base64 repartido en varias entradas (`<clave>` con «N:» y el primer trozo, `<clave>/part-i` el resto), con un máximo de unos 28 KB. Se escribe con CredWrite de advapi32 por PowerShell, sin módulos nativos ni PasswordVault. El script va en `-EncodedCommand` y los datos por stdin. Si falta un trozo, la entrada se lee como «sin credencial» y la persona vuelve a iniciar sesión. Si PowerShell no puede compilar el tipo (por ejemplo, en modo de lenguaje restringido), el almacén da error y el adaptador no se activa. `set` relee el valor y falla si no coincide.
- **Comentarios de documentos.** `/drives/{d}/items/{i}/comments` es la misma aproximación que usa el banco; en Graph v1.0 no existe tal cual. Hay que validarlo contra un inquilino real antes del piloto.
- **Gmail.** `gmail.metadata` no admite `q`, así que el adaptador recorre los `max_threads` hilos más recientes (300 por defecto). Leer menos solo puede omitir esperas antiguas, nunca inventarlas. Google no tiene delta: se lee completo con tope.
- **Calendario.** Se lee con `calendarView` y paginación, sin delta. La viabilidad lo midió en 1–2 peticiones por ciclo.
- **Jira.** Usa `/rest/api/3/search/jql` y, si el sitio devuelve 404, cae a `/rest/api/3/search`.
- **macOS.** Las órdenes del Llavero se prueban como construcción de órdenes (el secreto va solo en stdin), no contra el sistema real. Windows sí tiene una prueba real contra Credential Manager, que se ejecuta en el job de Windows de la CI.

## Pruebas

```bash
cd projects/soul-continuity
npm run test:adapters
npm run typecheck
```

Las pruebas usan:

- un servidor HTTP local (`test/adapters/mock-apis.ts`) que imita Graph, Google, Jira, Azure DevOps y GitHub, con paginación, delta, 410, 429, 401 y 403;
- el banco de Labs (`bench/`, sin cambios), ejecutado contra estos adaptadores por `test/adapters/bench-harness.ts` en dos modos: con los dobles en memoria y por HTTP con delta del correo entre los dos instantes.
