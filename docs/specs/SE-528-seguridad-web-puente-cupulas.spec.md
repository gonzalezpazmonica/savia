---
status: PROPOSED
priority: P1
developer_type: agent-single
created: 2026-11-13
author: Savia
phase: A
risk: L3
human_surface: true
related_specs: [SE-508, SE-510, SE-362, SE-343, SE-501]
origin: "Auditoría interna de seguridad del 2026-11-13: tres huecos verificados contra el código de main. Solo spec; sin tocar código."
timeline:
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "petición de la operadora: tres arreglos en una spec"
---

# SE-528 — Tres arreglos de seguridad: web, puente y cúpulas

## Problema (verificado en origin/main 65faf5138, 2026-11-13)

Una auditoría interna encontró tres huecos independientes. Esta spec es pública y los tres huecos siguen vivos en main hasta que se entreguen los slices, así que describe cada uno solo a nivel funcional: sin ficheros ni funciones afectadas, sin patrones de código ni valores por defecto y sin cadena de explotación. El detalle operativo vive en el registro privado de la operadora; quien implemente lo recibe de ella (decisión de la revisión de seguridad de la PR #1544).

- **H1 — savia-web**: parte del contenido que muestra la web no se sanea antes de pintarse, y la sesión la gestiona el propio cliente de forma que un script de la página podría leerla.
- **H2 — Puente**: acepta credenciales por un canal que deja rastro (URL, historiales, registros intermedios) y, en un modo de arranque concreto, atiende sin autenticar.
- **H3 — Cúpulas**: ante un fallo transitorio al leer la clave de firma de grants, el servidor la sustituye por una nueva, lo que invalida todos los grants emitidos sin dejar registro.
- Clientes propios del canal de credenciales antiguo: ninguno en el repositorio (solo lo menciona documentación probablemente obsoleta). Los clientes fuera del repo no se pueden inventariar desde aquí; de ahí la decisión abierta Q1.

## Quién lo explota y desde dónde

- H1: quien consiga que el contenido mostrado incluya HTML activo. No hace falta acceso a la red. Con VPN y operadora única el riesgo directo es bajo; el producto es para todo operador y, con varias personas, el robo de sesión cruza fronteras.
- H2: quien pueda leer los rastros de las URL; y, en el modo sin autenticar, quien alcance el puerto.
- H3: no hay atacante externo; es un fallo de disponibilidad con efecto de seguridad.

## Qué cubren ya otras specs (sin duplicar)

- **SE-508** (guard previo de efectos MCP): protege que un agente llame a herramientas MCP con efectos; no toca la web, el puente ni las cúpulas.
- **SE-510** (guardas sin bloqueos falsos): trata de los hooks de Savia; no toca la autenticación del puente ni el cliente web.
- Conclusión: ninguna cubre H1-H3. Se enlazan por contexto; no se absorbe nada de ellas.

## Puerta de comprensión — qué ve la persona

Solo el S2 cambia cómo se conecta una persona; el S1 cambia dónde se guarda la sesión.

**Antes**: la persona entra en savia-web con la dirección del puente y su token (lo pega en el formulario de acceso). La web lo guarda ella misma y lo manda en cada petición. Si alguien tenía un enlace con el token dentro, funcionaba y el token quedaba visible en la barra de direcciones.

**Después**: la persona sigue pegando el token una sola vez en el formulario. El puente lo comprueba y, si es válido, le devuelve una sesión opaca (no es el token) que el navegador guarda sin que la página pueda leerla. La persona no ve diferencia en el uso diario. Cambios visibles, según las decisiones abiertas: (a) un enlace con el token dentro deja de funcionar y devuelve «no autorizado» (Q1; con la recomendación, desde la entrega); (b) el arranque del puente sin autenticación solo es posible en la propia máquina y con el aviso bien visible (Q2); (c) las sesiones abiertas antes del cambio piden volver a pegar el token una vez (Q3).

**Decisiones abiertas para la operadora** (cambian algo visible):
- Q1. ¿Cuánto dura la transición del token en la URL? Recomendación: corte inmediato, porque no hay cliente propio que lo use y una transición mantiene el hueco abierto. Alternativa: 14 días con aviso en el registro.
- Q2. Arranque sin autenticación: ¿se elimina o se limita a la propia máquina? Propuesta: limitarlo (solo direcciones de bucle local); en cualquier otra, el arranque se niega.
- Q3. ¿Se acepta que todas las sesiones web abiertas pidan el token de nuevo una vez? Propuesta: sí.
- Q4. ¿La interfaz de escucha por defecto del puente debe ser solo local, con el acceso remoto como opción explícita? Ningún slice lo cambia sin tu decisión; afecta a quien hoy accede por VPN sin configurar nada.

## Slices (S1, S2 y S3 independientes; S4 depende de S2)

### S1 — savia-web: saneado de HTML y política de contenido (tier 2)

- Sanear con DOMPurify (o un renderizador de markdown que escape el HTML crudo) toda salida que se pinte como HTML: chat y visor de ficheros. Un único helper `renderMarkdownSafe` en `src/utils/`; los dos sitios lo usan.
- Cabecera `Content-Security-Policy` (sin `unsafe-inline` en scripts) como defensa en profundidad.

AC:
- AC-1.1 Test Vitest: `renderMarkdownSafe` con una imagen que lleva un manejador de evento en línea devuelve HTML sin ese manejador; montado el chat con ese contenido, el manejador no se ejecuta.
- AC-1.2 Idem con etiquetas de script, enlaces `javascript:` y elementos SVG con manejadores.
- AC-1.3 Caso positivo: markdown legítimo (títulos, listas, tablas, código, enlaces `https:`) se renderiza igual que antes.
- AC-1.4 Test que recorre `projects/savia-web/src` y falla si hay una inyección de HTML que no pase por `renderMarkdownSafe` (lista blanca explícita y vacía al cerrar).
- AC-1.5 La respuesta del servidor estático lleva la política de contenido sin `unsafe-inline` en scripts (test sobre la cabecera).

Reversión: revertir la PR; no cambia contratos.

### S2 — Puente: sesión opaca, credenciales solo por cabecera o sesión, fallo cerrado, CSRF/CORS (tier 3: autenticación, forzado aunque `risk-tier.py` mida 2)

Este slice es el único dueño de todo el cambio de autenticación del puente; ningún otro slice lo toca.
- Endpoint de login: valida el token y emite `Set-Cookie` con una sesión opaca (identificador aleatorio de servidor, no el token), `HttpOnly; Secure; SameSite=Strict; Path=/`, con caducidad y un logout que la invalida. El endpoint de login limita los intentos fallidos como el resto de la autenticación.
- La comprobación de autenticación acepta la cabecera `Authorization` o la cookie de sesión válida; una cookie manipulada, caducada o invalidada es 401.
- Dejar de leer credenciales de la URL. Transición (según Q1): se acepta con registro `SECURITY` y cabecera `Deprecation: true`; a la fecha de corte devuelve 401; después se borra el código.
- Fallo cerrado: sin token configurado y sin el modo abierto explícito, 401 en toda ruta protegida. Un indicador propio (`no_auth_mode`, solo lo activa el flag) distingue «sin token por error» de «modo abierto pedido». Un rechazo por falta de token configurado cuenta en el límite de intentos.
- Modo abierto (según Q2): solo con dirección de escucha de bucle local (`127.0.0.1`, `::1` o `localhost`); sin dirección explícita se aplica la de escucha por defecto y, si no es de bucle local, el arranque se niega con un mensaje que indica cómo pedir `--host 127.0.0.1`. Incluso en modo abierto el puente valida `Host` y `Origin` contra bucle local y la lista de orígenes permitidos, para que una página web abierta en el navegador local no pueda llamarlo.
- CSRF y CORS: con cookie de sesión, las rutas que cambian estado o ejecutan agentes exigen `Origin` dentro de una lista de orígenes permitidos. `Access-Control-Allow-Credentials: true` solo para orígenes de esa lista, nunca junto a `Access-Control-Allow-Origin: *`. Restricción de despliegue: la cookie `SameSite=Strict` solo viaja si web y puente se sirven desde el mismo sitio; con hosts distintos no hay sesión por cookie y vale la cabecera.
- Modo sin TLS: no recibe cookie `Secure`; se documenta como modo sin sesión por cookie.
- Actualizar `projects/savia-web/code-twin/frontend/composables.md` (documentación obsoleta).

AC:
- AC-2.1 Test: una petición protegida con la credencial en la URL y sin cabecera devuelve 401 (tras el corte); durante la transición devuelve 200 con `Deprecation: true` y una línea SECURITY en el registro.
- AC-2.2 Test: `Authorization: Bearer <válido>` sigue devolviendo 200; token inválido, 401, y cuenta en el límite de intentos.
- AC-2.3 Test de arranque: modo abierto con una dirección que no es de bucle local sale con código distinto de 0 y no abre el puerto; igual sin dirección explícita si la de por defecto no es de bucle local.
- AC-2.4 Test de handler: con el handler sin token configurado y `no_auth_mode` falso, una petición protegida devuelve 401, no 200, y cuenta en el límite de intentos.
- AC-2.5 Límite: modo abierto con `127.0.0.1`, con `::1` y con `localhost` arranca con el aviso y una petición protegida sin credenciales devuelve 200.
- AC-2.6 Test: el login con token válido devuelve `Set-Cookie` con `HttpOnly`, `Secure` y `SameSite=Strict`; el valor de la cookie no contiene el token.
- AC-2.7 Negativo: petición con cookie manipulada, caducada o tras logout devuelve 401.
- AC-2.8 Test: cookie válida con `Origin` ajeno a la lista en una ruta que ejecuta agentes devuelve 403; con `Origin` permitido, 200 y `Access-Control-Allow-Credentials: true`; nunca se combina con `Access-Control-Allow-Origin: *`.
- AC-2.9 Test: en modo abierto, una petición con `Origin` ajeno o `Host` que no es de bucle local devuelve 403.
- AC-2.10 Negativo: el login con token inválido devuelve 401 y, superado el límite, 429.

Reversión: revertir la PR; la cabecera `Authorization` no se retiró. Durante la transición, restaurar la aceptación de la URL es un cambio de una línea.

### S3 — Cúpulas: rotar solo si no existe (tier 3 por `risk-tier.py`)

- En el servidor de grants de `projects/savia-vaults`, leer la clave capturando el error: si el fichero no existe (`ENOENT`), rotar (primera creación). Cualquier otro error de lectura (permisos, bloqueo, E/S) o longitud distinta de 32 lanza un error tipado (`GrantKeyUnavailable`), se registra con el código y **no** rota. Quien llama a firmar o verificar falla cerrado.

AC:
- AC-3.1 Test: con la lectura simulada para fallar por bloqueo y por permisos, la lectura de la clave lanza `GrantKeyUnavailable` y el fichero de clave no cambia (mismo contenido tras la llamada).
- AC-3.2 Test: un grant firmado antes del error sigue verificándose después, una vez desaparece el error.
- AC-3.3 Caso positivo: sin fichero de clave se crea y se firma.
- AC-3.4 Límite: clave de 31 bytes lanza error y no rota (corrupción: decide la persona, no el servidor).
- AC-3.5 El error queda registrado con el código del sistema (comprobado en el test).

Reversión: revertir la PR. Efecto en operación: un fichero de clave corrupto ya no se repara solo; hay que borrarlo a mano (`rotate()` explícito, ya existente) y el mensaje de error lo dice.

### S4 — savia-web: sesión del cliente sin JavaScript (tier 3, depende de S2)

- El cliente deja de escribir la sesión con JavaScript y deja de guardar el token tras el login; usa la sesión opaca del puente con `credentials: 'include'`. La cabecera `Authorization` sigue disponible como alternativa.

AC:
- AC-4.1 Test e2e (Playwright): tras el login, ni la sesión ni el token son legibles desde JavaScript de la página.
- AC-4.2 Test: el cliente conserva el acceso a las rutas protegidas tras recargar la página con solo la cookie.
- AC-4.3 Negativo: con la cookie borrada o manipulada, el cliente vuelve al formulario de acceso.

Reversión: revertir la PR; el puente sigue aceptando la cabecera.

## Fuera de alcance

- Revocación y rotación periódica de tokens de usuario del puente.
- La política de CORS de otros servicios que sirven una especificación pública (se revisará por separado).
- El enlace de descarga firmado y con caducidad del servidor de cúpulas (diseño distinto); se anota como seguimiento.
- Cualquier cambio de código en esta PR: es solo spec.

## Riesgos

- S2 y S4 comparten el contrato de sesión: si divergen, la web no autentica. Mitigación: S2 es el único dueño del cambio del puente, se entrega antes que S4 y no retira la cabecera `Authorization`.
- Clientes no inventariados con la credencial en la URL (enlaces guardados): mitigados por la decisión Q1 y el aviso en el registro.
- S3 convierte un autoarreglo silencioso en un fallo visible: es el comportamiento deseado.
- Divulgación: esta spec es pública y los huecos están vivos hasta que se entreguen S1-S3. Por eso no lleva detalle explotable; el detalle está en el registro privado.

## Plan por slices

1. **S1** web, saneado (AC-1.1 a 1.5). 2. **S2** puente (AC-2.1 a 2.10). 3. **S3** cúpulas (AC-3.1 a 3.5). 4. **S4** web, sesión del cliente (AC-4.1 a 4.3).

S1, S2 y S3 no dependen entre sí. S4 se entrega después de S2. Cada slice, una PR.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| savia-web (S1, S4) | `projects/savia-web/src/**` | Mismo código; no depende del frontend de agentes |
| Puente (S2) | script del puente en `scripts/` | Mismo script; ningún binding |
| Cúpulas (S3) | servidor de grants en `projects/savia-vaults/src/server/` | Mismo servidor MCP |

### Verification protocol

- [ ] Funciona en runtime OpenCode: sin cambios de binding, el puente y la web son independientes del frontend
- [ ] Tests Vitest, BATS/pytest y de TS cubren cada caso y su par negativo
- [ ] Ningún hook nuevo; no hay registro en `savia-gates`

### Portability classification

- [x] **PURE_BASH / servicio**: independiente del frontend de agentes (Claude Code u OpenCode).

## Tier de riesgo (`scripts/risk-tier.py`, medido 2026-11-13)

| Slice | Contenido | Tier |
|---|---|---|
| S1 | saneado en chat y visor, política de contenido | 2 |
| S2 | autenticación del puente (login, cookie, CSRF/CORS, fallo cerrado) | 3 (el clasificador mide 2 al tocar solo código normal; se fuerza 3 por ser autenticación) |
| S3 | servidor de grants | 3 (ruta sensible) |
| S4 | almacén de sesión del cliente | 3 (ruta sensible) |

Tier 3: revisión humana explícita de cada PR (SE-362).

## Ficheros de esta spec

- Prueba de coherencia: `tests/bats/se528-spec-coherence.bats`.
- Registro: `docs/propuestas/planning.d/SE-528.json` y `docs/propuestas/LOG.d/SE-528-PROPOSED.md`.
- Fragmento de changelog: `CHANGELOG.d/se528-spec-seguridad.md`.

## Aprobación

Pendiente. La operadora decide Q1-Q3 y aprueba la spec; no se implementa nada antes.
