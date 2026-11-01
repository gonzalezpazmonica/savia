# Soul Continuidad · adaptador `web` (SE-490)

Lee webs sin API con el navegador ya instalado (Chrome o Edge) en un **perfil dedicado a Soul**, en solo lectura y sin modelo. Lo que no está en la receta se corta en la red, fuera del modelo y fuera de la página.

Viene de la preparación de Labs (`se490-prep/web`): formato de receta, validador, cortafuegos de tres capas, ejecutor, sitios sintéticos y batería AC-4e con sus 15 mutantes. Aquí se ha portado, comprobado con `tsc --strict` y ampliado con cinco defensas, cada una con su mutante.

- Node.js ≥ 22.6, TypeScript con `--experimental-strip-types`, sin compilar.
- Dependencia de ejecución: `playwright-core` 1.64.1, JavaScript puro. Desarrollo: `typescript` y `@types/node`.
- No se descargan navegadores: `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --ignore-scripts`.
- Navegador: `buscarNavegador()` o `SOUL_NAVEGADOR=<ruta>`. Chromium del sistema solo como último recurso, y entonces lo avisa.

```bash
npm run typecheck   # tsc --strict, sin emitir
npm run test:unit   # tests sin navegador
npm test            # todo: unitarios, ejecutor y batería completa (~4 min, Chrome sin interfaz)
npm run bateria     # solo la batería; --salida <dir> escribe el JSON
npm run mutantes    # la batería contra cada mutante, en serie (~1 h)
```

## Qué hay

| Ruta | Qué es |
|---|---|
| `receta/` | Formato `soul-receta-web/1` (`tipos.ts`), patrones de URL estrictos (`patrones.ts`) y validación fail-closed (`validar.ts`). |
| `cortafuegos/` | Decisión pura (`decision.ts`), las tres capas (`cortafuegos.ts`), y perfil dedicado, directorio de datos y detección del navegador (`perfil.ts`). |
| `adaptador/ejecutor.ts` | Ejecutor determinista: vistas de lista, acciones ligadas, prueba de humo, sesión caducada y Q1/Q2/Q4 (Q3 por diferencia). |
| `adaptador/contrato.ts` | `SourceAdapter` `web` del contrato compartido (`../contract/`): afirmaciones `web:*` y estado del adaptador. |
| `adaptador/navegador.ts` | Arranque del navegador sobre el perfil dedicado y lectura en un mundo aislado. |
| `adaptador/vigilancia.ts` | Sin receta: solo «esta página cambió», con el enlace. |
| `adaptador/activacion.ts` · `grabacion.ts` · `cli-grabacion.ts` | Puerta de las recetas experimentales y su validación contra el tráfico grabado del operador. |
| `recetas/sinteticas/` | Recetas de los cuatro sitios del banco (`estable`). |
| `recetas/producto/` | Plantillas genéricas de Outlook (correo y calendario), Teams y OneDrive/SharePoint en la web: **experimentales y desactivadas**. |
| `banco/` · `bench/` · `verdad/` | Sitios sintéticos, batería AC-4e y mutantes, y la verdad escrita antes del código. |
| `resultados/` | `bateria-ninguno.json` y `mutantes.json` de la última ejecución. |

## Cortafuegos: tres capas con la misma decisión

`decidirHttp(receta, estado, petición)` es pura. Sigue este orden: esquema, login (sesión caducada), renovación de sesión (patrón exacto, sin comodines, y nunca una URL de acción), lista de URLs, acción en la URL concreta, **otro origen**, acción en curso, endpoint de operaciones solo por `POST`, `GET`/`HEAD`, y `POST` con su operación cotejada con la de la consulta. Todo lo demás se corta.

- **A · Guardia del navegador** (CDP `Fetch`, petición y respuesta). Ve cada salto de una redirección, las descargas por `<a download>`, el favicon y los scripts de workers. Corta adjuntos y detecta 401. Sin ella no se ejecuta.
- **B · `context.route`.** Aplica la misma decisión. Responde 204 a una navegación cortada y, si la petición pasa, usa `continue`.
- **C · WebSocket y workers.** Solo salen los mensajes de texto exactos de mantenimiento; un mensaje binario nunca sale. Los workers dedicados se quedan en pausa y `--disable-shared-workers` elimina los compartidos.

El canal de control va por tubería (`--remote-debugging-pipe`), nunca por puerto. El proceso del navegador recibe `HOME` y `XDG_*` dentro del perfil dedicado. La página no puede enviar formularios.

### Defensas añadidas en el producto

| Defensa | Por qué | Mutante que la quita |
|---|---|---|
| **Login federado (SSO).** `sesion.login` admite un origen entero (`https://login.example`). | Los clientes reales caducan hacia otro origen. Antes eso acababa en `DESACTIVADA` por la prueba de humo, no en `SESION_CADUCADA`. | `sin_login_externo` |
| **Patrones absolutos solo para subrecursos.** `urls` admite `https://cdn.example/…`, pero navegar a otro origen se corta (`otro_origen`). | Los clientes reales cargan scripts o leen datos de otro origen. La página nunca debe salir del suyo. | `absoluto_navegable` |
| **Lectura en un mundo aislado** (`Page.createIsolatedWorld`). | Con `$$eval` en el mundo de la página, un script hostil podía falsear lo extraído parcheando `getAttribute`. Ahora el banco lo intenta. | `extraccion_mundo_principal` |
| **Vigilancia sin receta, siempre sin JavaScript.** | Leer una página desconocida no debe ejecutar su código. | `vigilancia_con_js` |
| **Recetas experimentales tras un recibo.** No abren el navegador sin un recibo local, ligado a la huella exacta de la receta. | Las plantillas de clientes reales no están validadas contra tráfico real. | `experimental_sin_recibo` |
| **Endpoint de operaciones solo por `POST`.** Un `GET` o `HEAD` a una URL de `post_lectura` se corta (`metodo`), también como navegación. | Por `GET` la operación iría en la URL y no se clasificaría: `GET /owa/service.svc?action=MarkAllItemsAsRead` pasaba como «lista». | `post_lectura_por_get` |
| **`estable` solo en el banco.** Sin recibo, solo se ejecuta una receta `estable` de origen local (bucle `127.0.0.0/8`, `localhost`, `[::1]`) y solo si el código del banco lo indica (`banco` en `Dependencias`/`Opciones`, nunca en la receta ni en `params`). En producto toda receta necesita recibo, también las de servicios que corren en local. | El campo `estado` lo escribe la propia receta: cambiarlo en una plantilla copiada saltaba la puerta. Y un panel o túnel local es un servicio real. | `experimental_sin_recibo` |
| **Operación de la consulta cotejada.** Si la consulta lleva un parámetro con el nombre de la cabecera (o de la última clave de `cuerpo_json`), su valor tiene que ser la operación declarada; si no, se corta y la receta se desactiva (`operacion_url_distinta`). | Un servidor puede ejecutar la operación de la URL y no la de la cabecera: `?action=UpdateItem` con `action: FindItem`. | `operacion_url_sin_cotejar` |

## Perfil dedicado y credenciales

- `prepararPerfilSoul(directorioDatos())` crea un perfil persistente en `<datos>/web/perfil` con la marca `.perfil-soul`.
  - Se rechaza si está dentro de un perfil personal de Chrome, Edge, Chromium o Firefox.
  - En cada preparación reimpone las preferencias que apagan el gestor de contraseñas y el autorrelleno.
- El directorio de datos es el del núcleo (`SOUL_DATA_DIR`, o el del sistema: Linux `$XDG_DATA_HOME/savia/soul-continuity`, macOS `~/Library/Application Support/Savia/soul-continuity`, Windows `%LOCALAPPDATA%\Savia\soul-continuity`). En producto, `src/core/connectors.ts` fija perfil, huellas, desactivadas y recibos dentro de `<datos>/web/`, y `soul uninstall` o `soul revoke web` lo borran entero.
- El operador inicia sesión **a mano** en ese perfil, y solo en las webs que da a Soul. Soul no guarda contraseñas, no rellena credenciales y no inyecta cookies: el parámetro `cookies` solo existe para el banco.
- Sesión caducada: parada limpia, 0 elementos y el aviso «Vuelve a iniciar sesión en X en el perfil de Soul».
- **Claves de las cookies (Linux):** el perfil persistente arranca con `--password-store=gnome-libsecret`: la clave que cifra sus cookies queda en el llavero del sistema, como los tokens de Soul. Sin bus de sesión (ni `DBUS_SESSION_BUS_ADDRESS` ni `XDG_RUNTIME_DIR`), el perfil no se abre. El perfil temporal del banco sigue con `basic` porque se borra al cerrar. **Riesgo residual:** si el bus existe pero el llavero no responde, Chromium puede caer a su clave fija sin avisar; eso no se ha verificado contra un llavero real. Protege el directorio de datos como una credencial. Los ficheros de estado que escribe Soul (`desactivadas`, huellas, recibos) van con 0600.

## Sin receta: «esta página cambió»

`vigilarPagina({ vigilada: { id, sitio, url }, … })` pasa por el mismo cortafuegos con una receta mínima: esa URL exacta, sin JavaScript, sin `POST`, sin WebSocket y sin acciones. Guarda la huella SHA-256 del texto, nunca el texto. Los estados posibles son:

- `PRIMERA_VISITA`, `SIN_CAMBIOS` o `CAMBIADA`, con el enlace;
- `SESION_CADUCADA`, si responde 401 o salta a una página de inicio de sesión (la ruta o el servidor llevan `login`, `signin`, `auth`, `oauth`, `sso`, `saml`, `adfs`… como palabra entera, también un proveedor de identidad de otro origen);
- `REDIRIGIDA`, si salta a cualquier otra URL (por ejemplo `/avisos` → `/avisos/`): el aviso da el destino, sin consulta, para corregir la URL vigilada;
- `ERROR`.

Una URL con aspecto de acción (`approve`, `logout`, `confirm…`) se rechaza al darla de alta, también con el verbo seguido de una extensión o de `;` (`/logout.aspx`) o pegado en camelCase en el camino (`/api/approveTask`). En la consulta no se parte el camelCase: ahí van nombres de operación, que clasifica `post_lectura`.

## Recetas de clientes reales: experimentales y desactivadas

Las plantillas de `recetas/producto/` **no** se han validado contra tráfico real. URLs, operaciones y selectores son de partida. Por eso:

- llevan `"estado": "experimental"` y no se ejecutan sin un recibo de validación en `<datos>/web/validaciones/`;
- el recibo queda ligado a la huella de la receta ya completada (JSON canónico, sin depender del orden de claves): cualquier cambio lo invalida;
- el recibo no va firmado: la frontera de confianza es la cuenta local del operador. Quien pueda escribir en `<datos>/web/validaciones/` puede activar una receta con un recibo escrito a mano, igual que podría editar el perfil o la configuración. El recibo protege de un error (activar una plantilla sin validarla), no de un atacante con acceso a tu cuenta;
- si el cliente cambia, la prueba de humo desactiva la receta y avisa: «La receta de X dejó de ser fiable». Una operación `POST` desconocida hace lo mismo, sin devolver datos.
- un fallo de carga (red caída, DNS, estado HTTP no 2xx sin corte del cortafuegos) es `ERROR` transitorio y **no** desactiva la receta. La desactivación persiste en el fichero `desactivadas`; tras revisar la receta, se reactiva con `AlmacenRecetas.reactivar(id)` o quitando su entrada. Si ese fichero es ilegible, no se ejecuta ninguna receta hasta revisarlo.

### Procedimiento del operador para activar una receta

Todo ocurre en local y fuera de cualquier repositorio. La grabación lleva datos de la empresa (N4).

1. **Abre el perfil de Soul** con el navegador instalado. En Linux, con el perfil por defecto:
   `google-chrome --password-store=gnome-libsecret --user-data-dir="$HOME/.local/share/savia/soul-continuity/web/perfil"`.
   Inicia sesión en el cliente, y solo en él.
2. **Graba solo lectura.** Abre DevTools, pestaña Red, y marca «Conservar registro». Carga la página de la receta (por ejemplo, la bandeja de entrada en vista de lista) y espera a que se pinte.
   - **No abras elementos**, no respondas y no pulses nada más.
   - Si el cliente lanza escrituras solo (marcar como leído, sincronizar), aparecerán en la grabación. Es lo que se busca: hay que clasificarlas.
3. **Exporta el HAR** con contenido a `<datos>/web/grabaciones/` (permisos 0700). Nunca dentro de un repositorio.
4. **Copia la plantilla** a `<datos>/web/recetas/` y complétala. Las variables (`{inquilino}`, `{region}`) salen de la barra de direcciones y de la grabación.
5. **Valida:**
   ```bash
   npm run validar-grabacion -- --receta <datos>/web/recetas/outlook-web-correo.json \
     --har <datos>/web/grabaciones/outlook.har --var inquilino=… --var region=…
   ```
   El informe está enmascarado: sin valores de consulta, sin cuerpos y sin identificadores largos. La validación falla si:
   - un `POST` a una URL de lectura no declara su operación (no se distingue lectura de escritura: la receta no se publica);
   - aparece una operación desconocida;
   - una lectura tiene nombre de escritura;
   - un documento GraphQL de «lectura» trae `mutation`;
   - un `POST` a un endpoint declarado no sale ni como lectura ni como escritura conocida: por ejemplo, la consulta repite la operación con otro valor (`operacion_url_distinta`) o la URL parece de acción. El cortafuegos lo cortaría y la validación no lo da por bueno;
   - la grabación no cubre las páginas de la receta.
6. **Ajusta la receta** con el informe: operaciones en `lectura` o `escritura_conocida`, y URLs de la lista. Repite hasta que pase. **No relajes la regla.** Si el cliente no permite distinguir lectura de escritura, esa fuente se queda sin ruta web.
7. **Emite el recibo** repitiendo la orden con `--emitir-recibo`.
8. **Ejecuta la batería** (`npm test`) para confirmar que el cortafuegos de esta instalación sigue dando 0 efectos en el banco.
9. **Borra la grabación** (`<datos>/web/grabaciones/`). El recibo no contiene datos de la grabación.

La validación reproduce cada petición grabada por la misma decisión del cortafuegos. **No** sustituye a la batería con mutaciones medidas en el servidor: el servidor real no se puede instrumentar. La garantía de 0 efectos la dan el cortafuegos, probado en el banco, y la lista cerrada que fija la grabación.

## Adaptador del contrato (`adaptador/contrato.ts`)

`crearAdaptadorWeb()` cumple `SourceAdapter` de `src/contract/adapter.ts`:

- **Parámetros** (`params` de la fuente): `ejecutable` (navegador instalado) y `perfil` (perfil dedicado de Soul) son obligatorios (en el producto los fija el núcleo: el navegador sale de `SOUL_NAVEGADOR` o de las rutas conocidas, nunca de `config.json`); sin ellos, `not_configured`. Además `recetas`, `vigiladas`, `validaciones`, `desactivadas` (obligatorio si hay recetas: sin él, una receta desactivada se reintentaría en la siguiente lectura) y `huellas` (obligatorio si hay páginas vigiladas). Sin recetas ni páginas vigiladas, `not_configured`. El adaptador no supone directorios: para usar los recibos que emite `validar-grabacion`, `validaciones` tiene que apuntar a `<datos>/web/validaciones` (`dirValidacionesPorDefecto`).
- **Afirmaciones.** Un elemento en Q1 o Q2 de la receta es `web:task_assigned:<receta>~<id>`, con `awaiting_operator` si está en Q2. Uno que solo está en Q4 es `web:dated_commitment:<receta>~<id>`. Una página vigilada que cambió es `web:web_page_change:<sitio>~<id>`, cerrada y con `event_at`. Las partes de la referencia van codificadas en URL, sin `:`, espacios ni `~`. `due_at` sale del primer campo `vence`, `limite` o `fecha` con forma `AAAA-MM-DD`. El título, del primer campo `titulo`, `asunto`, `nombre`, `concepto` o `resumen`, limpio y marcado `untrusted_text`. `sender_auth` es siempre `unknown`.
- **Estados.** Sesión caducada (también la de una página vigilada) → `session_expired`; una página vigilada redirigida a otra URL que no es el inicio de sesión → `error`, porque no se arregla iniciando sesión; una página vigilada que no carga por la red o responde con un estado HTTP de error (404, 5xx) es `error`, no sesión caducada ni «página cambiada». Un fichero de huellas ilegible también es `error`: no se trata como primera visita ni se sobrescribe. Prueba de humo u operación nueva → `recipe_disabled`. Fallo de lectura → `error`. Una receta configurada sin recibo válido no abre el navegador y da `recipe_disabled` con su aviso, aunque haya otras fuentes que sí funcionen: no se omite en silencio. Una página vigilada mal escrita (sin `id`, `sitio` o `url`, o con URL de acción, comodín o credenciales) → `not_configured`.
- **Fail-closed.** Si falla cualquier receta o página, el adaptador entero no aporta afirmaciones. Manda `session_expired` sobre `error` y sobre `recipe_disabled`, porque el operador puede arreglarlo. Las huellas de las páginas vigiladas solo se guardan si el adaptador entrega, para que un cambio descartado vuelva a verse en la siguiente lectura; si no se pueden guardar, el resultado es `error` y no se entrega el cambio. El directorio de huellas se crea si falta.
- Las recetas de `params.recetas` pasan siempre por `validarReceta`; una inválida da `not_configured` sin abrir el navegador.
- No usa `ctx.transport` ni `ctx.credentials`. Navega con el navegador sobre el perfil dedicado; la sesión es la que inició el operador ahí.

## Resultados (Chrome, Linux)

Los números exactos de la última ejecución están en `resultados/`.

- **Batería: 356 de 356 comprobaciones bien** con el cortafuegos real. Son las 243 de Labs, 102 de los escenarios nuevos (SSO, receta experimental, vigilancia, extracción falseada, navegación a otro origen y operación en la URL) y 11 comprobaciones propias de defensas que antes solo se veían en métricas compartidas: cada una exige en el registro del cortafuegos un corte con el motivo de esa defensa.
- **Mutantes: 22 de 22 muertos**: los 15 de Labs y los 7 nuevos, con informe de cada uno (la última ejecución, con `--paralelo 3`). Un mutante solo cuenta como muerto si falla una comprobación de **su** defensa (`bench/mapa-mutantes.ts`); los fallos ajenos se cuentan aparte. Ningún id de la batería casa con dos mutantes: `test/mapa-mutantes.test.ts` lo comprueba contra los ids reales de `resultados/bateria-ninguno.json`.
- Cada informe lleva `huella_codigo`, la huella del código y los datos que decide la batería. Un informe de otro código no cuenta (`SIN_INFORME`, marcado `obsoleto`), y un test exige que los resultados versionados sean del código actual.
- `tsc --strict` limpio (el `tsconfig` del adaptador y el del proyecto) y 153 tests en verde, 23 de ellos del adaptador del contrato.

## Lo que queda abierto

- **Recetas de clientes reales sin validar.** Sin tráfico real grabado, su contenido es de partida. Teams usa WebSocket y workers que v1 no admite. Si el cliente no pinta sin ellos, la receta no se publica.
- **Operación en la ruta.** OneDrive y SharePoint pueden listar con `RenderListDataAsStream`, con la operación en la URL. El formato v1 solo la lee de una cabecera o del cuerpo JSON, así que esa receta no pasaría.
- **Workers.** No arrancan en v1. Habilitarlos exige un *shim* de `WebSocket` dentro del worker antes de reanudarlo.
- **Cobertura con JavaScript hostil:** la precisión se mantiene en 1,0, pero la cobertura cae (Q1: 0,5), igual que en Labs. Es una denegación, no una fuga.
- **Solo probado en Linux con HTTP de loopback y Chrome.**
  - Sin probar: HTTPS, Edge, Windows y macOS.
  - Sin comprobar: dónde escribe Chrome `Crash Reports` en Windows y macOS. En Linux se cierra dando `HOME` y `XDG_*` dentro del perfil.
  - La comprobación del canal de depuración por tubería usa `/proc`, así que solo funciona en Linux.
- **Varias ejecuciones sobre el mismo perfil persistente** no pueden ir a la vez (bloqueo del navegador). Quien orqueste los adaptadores debe ponerlas en serie.
