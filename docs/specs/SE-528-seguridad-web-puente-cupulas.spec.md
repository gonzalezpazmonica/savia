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
origin: "Auditoría interna de seguridad del 2026-11-13: tres frentes de endurecimiento. Solo spec; sin tocar código."
timeline:
  - from: "2026-11-13"
    learned: "2026-11-13"
    value: "PROPOSED"
    source: "petición de la operadora: tres arreglos en una spec"
---

# SE-528 — Tres arreglos de seguridad: web, puente y cúpulas

## Problema (auditoría interna del 2026-11-13)

Una auditoría interna encontró tres frentes de endurecimiento independientes. Esta spec es pública y los tres siguen sin entregar, así que fija solo requisitos objetivo: sin ficheros, funciones, símbolos, valores de configuración, umbrales ni estado actual de los componentes. El detalle operativo vive en el registro privado de la operadora; quien implemente lo recibe de ella (decisión de la revisión de la PR #1544).

- **H1 — savia-web**: endurecer el cliente web (contenido y sesión).
- **H2 — Puente**: endurecer la autenticación del puente.
- **H3 — Cúpulas**: garantizar la integridad de la clave de firma de grants.

## Riesgo y exposición

Con una operadora única y acceso por VPN el riesgo directo es bajo; el producto es para todo operador y, con varias personas, un fallo de sesión o de autenticación cruza fronteras. El detalle de explotabilidad es privado.

## Qué cubren ya otras specs (sin duplicar)

- **SE-508** (guard previo de efectos MCP): protege que un agente llame a herramientas MCP con efectos; no toca la web, el puente ni las cúpulas.
- **SE-510** (guardas sin bloqueos falsos): trata de los hooks de Savia; no toca la autenticación del puente ni el cliente web.
- Conclusión: ninguna cubre H1-H3. Se enlazan por contexto; no se absorbe nada de ellas.

## Puerta de comprensión — qué ve la persona

Solo el S2 y el S4 cambian cómo se conecta una persona.

**Flujo**: la persona entra en savia-web con la dirección del puente y pega su token una sola vez en el formulario. El puente lo comprueba y, si es válido, le devuelve una sesión opaca (no es el token) que el navegador guarda sin que la página pueda leerla. La persona no ve diferencia en el uso diario. Comportamiento visible, según las decisiones de la operadora: (a) los accesos por un canal de credenciales no admitido devuelven «no autorizado» desde la entrega, sin periodo de transición (Q1); (b) el arranque del puente sin autenticación solo es posible en la propia máquina y con el aviso bien visible (Q2); (c) las sesiones web abiertas antes de la entrega piden volver a pegar el token una vez (Q3); (d) en un despliegue sin sesión por cookie (web y puente en sitios distintos, o sin TLS) el token vive solo en la memoria de la pestaña y la persona lo pega de nuevo al recargar. Esta decisión (d) la propone la orquestadora tras la revisión de la PR #1544 y queda pendiente de confirmación de la operadora al aprobar la spec.

**Decisiones de la operadora (2026-11-13)**. Registro de la orquestadora, no texto literal. La operadora respondió por pregunta interactiva y en las tres eligió la opción recomendada:
- Q1. Corte inmediato de todo canal de credenciales que no sea la cabecera ni la sesión, sin transición: responde 401 desde la entrega. Una transición alarga la exposición.
- Q2. El arranque sin autenticación se limita a direcciones de bucle local; en cualquier otra, el arranque se niega.
- Q3. Se acepta que las sesiones web abiertas pidan el token una vez.

## Slices (S1, S2 y S3 independientes; S4 depende de S2)

### S1 — savia-web: saneado de HTML y política de contenido (tier 2)

- Toda salida que se pinte como HTML pasa por un único punto de saneado (un sanitizador reconocido o un renderizador que escape el HTML crudo); todos los puntos de pintado lo usan.
- Cabecera `Content-Security-Policy` (sin `unsafe-inline` en scripts) como defensa en profundidad.

AC:
- AC-1.1 Test Vitest: el punto de saneado con contenido que incluye HTML activo devuelve HTML sin elementos ni atributos ejecutables; montado el componente de pintado con ese contenido, no se ejecuta nada.
- AC-1.2 Idem con cada clase de HTML activo: etiquetas ejecutables, URL con esquema ejecutable y SVG con contenido activo.
- AC-1.3 Caso positivo: markdown legítimo (títulos, listas, tablas, código, enlaces `https:`) se renderiza igual que antes.
- AC-1.4 Test que recorre el código de la web y falla si hay una inyección de HTML que no pase por el punto de saneado (lista blanca explícita y vacía al cerrar).
- AC-1.5 La respuesta del servidor estático lleva la política de contenido sin `unsafe-inline` en scripts (test sobre la cabecera).

Reversión: revertir la PR; no cambia contratos.

### S2 — Puente: sesión opaca, credenciales solo por cabecera o sesión, fallo cerrado, CSRF/CORS (tier 3: autenticación, forzado aunque `risk-tier.py` mida 2)

Este slice es el único dueño de todo el cambio de autenticación del puente; ningún otro slice lo toca.
- Endpoint de login: valida el token y emite `Set-Cookie` con una sesión opaca (identificador aleatorio de servidor, no el token), `HttpOnly; Secure; SameSite=Strict; Path=/`, con caducidad y un logout que la invalida. El endpoint de login limita los intentos fallidos como el resto de la autenticación.
- La comprobación de autenticación acepta la cabecera `Authorization` o la cookie de sesión válida; una cookie manipulada, caducada o invalidada es 401.
- Las credenciales solo se aceptan por la cabecera `Authorization` o la cookie de sesión; cualquier otro canal se rechaza con 401 desde la entrega, sin transición (Q1).
- Fallo cerrado: sin token configurado y sin el modo abierto explícito, toda ruta protegida responde 401; el modo abierto solo lo activa una petición explícita. Ese rechazo se registra con `SECURITY` y un mensaje que apunta a la configuración, pero no cuenta en el límite de intentos (si contara, un tercero podría agotar el límite y bloquear al operador legítimo, y se taparía la causa real).
- Modo abierto (Q2): solo si la dirección efectiva de escucha, ya resuelta, es de bucle local (`127.0.0.1` o `::1`; `localhost` solo si resuelve a una de ellas); en cualquier otro caso el arranque se niega con un mensaje que indica cómo pedir la dirección local. Incluso en modo abierto el puente valida `Host` y `Origin` contra bucle local y la lista de orígenes permitidos, para que una página web abierta en el navegador local no pueda llamarlo.
- CSRF y CORS: con cookie de sesión, las rutas que cambian estado o ejecutan agentes, y el propio login, exigen `Origin` dentro de una lista de orígenes permitidos; una petición con cookie que cambia estado y no trae `Origin` es 403. `Access-Control-Allow-Credentials: true` solo para orígenes de esa lista, nunca junto a `Access-Control-Allow-Origin: *`. Restricción de despliegue: la cookie `SameSite=Strict` solo viaja si web y puente se sirven desde el mismo sitio; con hosts distintos no hay sesión por cookie y vale la cabecera.
- Modo sin TLS: no emite cookie de sesión; solo vale la cabecera. Se documenta como modo sin sesión por cookie.
- Login desde un cliente que no es un navegador (sin `Origin`): permitido con token válido; solo se rechaza un `Origin` presente y ajeno a la lista.
- Credenciales por un canal no admitido y por la cabecera a la vez: 401 (el canal no admitido se rechaza siempre, no se ignora).
- Límite de intentos: la clave del límite es el cliente (dirección de origen), nunca global, para que un tercero no pueda bloquear al operador legítimo. Los intentos por un canal no admitido también cuentan.
- Preflight y streaming: las peticiones `OPTIONS` con credenciales solo se aceptan de orígenes de la lista; las rutas de streaming usan la cabecera o la cookie de sesión como el resto.
- Orden de entrega: S2 no se despliega sin S4 si el cliente web depende de un canal que S2 corta; se entregan coordinados o S4 antes de activar el corte (Q1).
- Endpoint de estado de sesión: responde 200 si la cookie de sesión es válida y 401 si no, sin cuerpo con datos sensibles; es el contrato que usa el cliente (S4) para saber si la sesión sigue vigente sin leer la cookie.
- Actualizar la documentación del cliente web para que describa solo los canales admitidos.

AC:
- AC-2.1 Test, con token configurado: una petición protegida por un canal no admitido, con o sin cabecera `Authorization` válida, devuelve 401 desde la entrega (Q1); no hay transición: ni respuesta 200 ni cabecera de obsolescencia en ningún caso.
- AC-2.2 Test: `Authorization: Bearer <válido>` sigue devolviendo 200; token inválido, 401, y cuenta en el límite de intentos.
- AC-2.3 Test de arranque: modo abierto cuya dirección efectiva de escucha no es de bucle local sale con código distinto de 0 y no abre el puerto; un nombre que resuelve fuera de bucle local también se niega.
- AC-2.4 Test de handler: sin token configurado y sin modo abierto, una petición protegida devuelve 401, queda registrada y no incrementa el contador de intentos fallidos.
- AC-2.5 Límite: modo abierto con `127.0.0.1`, con `::1` y con `localhost` (resuelto a bucle local) arranca con el aviso y una petición protegida sin credenciales devuelve 200.
- AC-2.6 Test, con TLS: el login con token válido devuelve `Set-Cookie` con `HttpOnly`, `Secure` y `SameSite=Strict`; el valor de la cookie no contiene el token.
- AC-2.7 Negativo: petición con cookie manipulada, caducada o tras logout devuelve 401.
- AC-2.8 Test: cookie válida con `Origin` ajeno a la lista en una ruta que ejecuta agentes devuelve 403; con `Origin` permitido, 200 y `Access-Control-Allow-Credentials: true`; nunca se combina con `Access-Control-Allow-Origin: *`.
- AC-2.9 Test: en modo abierto, una petición con `Origin` ajeno o `Host` que no es de bucle local devuelve 403.
- AC-2.10 Negativo: el login con token inválido devuelve 401 y, superado el límite, 429; el límite es por cliente: otro cliente distinto sigue pudiendo iniciar sesión.
- AC-2.11 Negativo: con cookie de sesión válida, una ruta que cambia estado sin `Origin` devuelve 403.
- AC-2.12 Negativo: el login con `Origin` ajeno a la lista devuelve 403.
- AC-2.13 Test: el login con token válido y sin `Origin` (cliente que no es un navegador) devuelve 200.
- AC-2.14 Test, sin TLS: el login no emite cookie de sesión y la cabecera `Authorization` sigue devolviendo 200.
- AC-2.15 Test: el endpoint de estado de sesión devuelve 200 con cookie válida y 401 con cookie ausente, manipulada, caducada o tras logout.
- AC-2.16 Test: los intentos por un canal no admitido cuentan en el límite de intentos del cliente y superado el límite devuelven 429.
- AC-2.17 Test: una petición `OPTIONS` con credenciales desde un origen de la lista devuelve las cabeceras CORS; desde un origen ajeno, ninguna cabecera de permiso.
- AC-2.18 Test: una ruta de streaming responde 200 con cookie válida o cabecera válida y 401 sin credenciales.

Reversión: revertir la PR; la cabecera `Authorization` no se retiró. Admitir de nuevo otro canal, si hiciera falta, es un cambio acotado y una decisión nueva de la operadora.

### S3 — Cúpulas: integridad de la clave de firma (tier 3 por `risk-tier.py`)

- La clave de firma de grants es estable: solo se crea en la primera creación. Ante cualquier fallo de acceso o una clave inválida, se lanza un error tipado de «clave no disponible», se registra con el código del sistema y la clave no cambia. Quien llama a firmar o verificar falla cerrado.

AC:
- AC-3.1 Test: con la lectura simulada para fallar de dos maneras distintas, la lectura de la clave lanza el error de «clave no disponible» y el fichero de clave no cambia (mismo contenido tras la llamada).
- AC-3.2 Test: un grant firmado antes del error sigue verificándose después, una vez desaparece el error.
- AC-3.3 Caso positivo: sin fichero de clave se crea y se firma.
- AC-3.4 Límite: una clave de longitud inválida lanza el error de «clave no disponible» y el fichero de clave no cambia (la regeneración la decide la persona, no el servidor).
- AC-3.5 El error queda registrado con el código del sistema (comprobado en el test).

Reversión: revertir la PR. Efecto en operación: la regeneración de la clave es una acción explícita de la persona y el mensaje de error lo dice.

### S4 — savia-web: sesión del cliente sin JavaScript (tier 3, depende de S2)

- Con sesión por cookie (mismo sitio y TLS): el cliente no conserva el token tras el login, usa la sesión opaca del puente con `credentials: 'include'` y comprueba su vigencia con el endpoint de estado de sesión (S2).
- Sin sesión por cookie (sitios distintos o sin TLS): el cliente envía `Authorization` con el token guardado solo en memoria de la pestaña; nunca en almacenamiento del navegador. Tras recargar, vuelve al formulario (decisión (d)).

AC:
- AC-4.1 Test e2e (Playwright), con sesión por cookie: tras el login, ni la sesión ni el token son accesibles para scripts de la página ni están en el almacenamiento del navegador.
- AC-4.2 Test, con sesión por cookie: tras recargar la página, el cliente comprueba la sesión con el endpoint de estado y conserva el acceso a las rutas protegidas con solo la cookie.
- AC-4.3 Negativo: con la cookie borrada o manipulada, el endpoint de estado responde 401 y el cliente vuelve al formulario de acceso.
- AC-4.4 Test, sin sesión por cookie: tras el login las rutas protegidas responden 200 con `Authorization` y el token no está en el almacenamiento del navegador.
- AC-4.5 Negativo, sin sesión por cookie: tras recargar la página el cliente vuelve al formulario de acceso.

Reversión: revertir la PR; el puente sigue aceptando la cabecera.

## Fuera de alcance

- Revocación y rotación periódica de tokens de usuario del puente.
- La política de CORS de otros servicios y los enlaces de descarga del servidor de cúpulas: se revisan por separado.
- Cualquier cambio de código en esta PR: es solo spec.

## Riesgos

- S2 y S4 comparten el contrato de sesión: si divergen, la web no autentica. Mitigación: S2 es el único dueño del cambio del puente, se entrega antes que S4 y no retira la cabecera `Authorization`; S4 conserva el camino por cabecera (en memoria) para los despliegues sin sesión por cookie.
- Clientes externos no inventariados que usen credenciales fuera de la cabecera y la sesión: aceptado por la decisión Q1 (corte inmediato); el aviso queda en el registro de la entrega.
- Divulgación: esta spec es pública y los tres frentes siguen abiertos hasta que se entreguen S1-S4. Por eso solo fija requisitos objetivo; el detalle está en el registro privado.

## Plan por slices

1. **S1** web, saneado (AC-1.1 a 1.5). 2. **S2** puente (AC-2.1 a 2.18). 3. **S3** cúpulas (AC-3.1 a 3.5). 4. **S4** web, sesión del cliente (AC-4.1 a 4.5).

S1, S2 y S3 no dependen entre sí. S4 se entrega después de S2 y coordinado con su corte (ver S2, orden de entrega). Cada slice, una PR.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| savia-web (S1, S4) | código de la web | Mismo código; no depende del frontend de agentes |
| Puente (S2) | script del puente | Mismo script; ningún binding |
| Cúpulas (S3) | servidor de grants de las cúpulas | Mismo servidor MCP |

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

Pendiente. Q1-Q3 están decididas (2026-11-13). La operadora aprueba la spec con un comentario en la PR; no se implementa nada antes.

Condiciones de fusión: (1) revisión humana de confidencialidad de la operadora sobre esta PR, porque la prueba bats comprueba forma y una lista negra de patrones, no el contenido ni la ausencia de detalle; (2) decisión de la operadora, por escrito, sobre el historial de la rama, que conserva versiones anteriores con más detalle (p. ej. una rama nueva sin ese historial en lugar de fusionar esta).
