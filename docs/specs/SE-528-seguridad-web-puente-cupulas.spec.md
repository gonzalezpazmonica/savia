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

Una auditoría interna encontró tres huecos independientes. El primero y el segundo se encadenan; el tercero es aparte.

### H1 — savia-web: HTML sin sanear y sesión legible por scripts

- `projects/savia-web/src/pages/ChatPage.vue:111` pinta `v-html="renderMd(msg.content)"`. `renderMd` (`:11-14`) es `marked.parse(...)` sin saneado; `marked` no elimina HTML crudo. Lo que escribe el modelo o una herramienta llega tal cual al DOM.
- `projects/savia-web/src/components/files/FileViewer.vue:200` pinta `v-html="markdownBody"` con el contenido de cualquier fichero abierto en el visor (`:77-83`), también sin sanear.
- Son los dos únicos `v-html`/`innerHTML` con código propio en `projects/savia-web/src` (grep exhaustivo; el S1 repite el grep como AC).
- `projects/savia-web/src/stores/auth.ts:17` escribe la sesión con JS: `document.cookie = savia_session=...; path=/; SameSite=Lax`, sin `HttpOnly` ni `Secure`. La cookie contiene el token del puente en claro (`:16`). `:27` hace lo mismo con `savia_connection` (también el token, `max-age` de un año).
- Cadena: un fichero markdown o una respuesta con `<img src=x onerror=...>` ejecuta script en el origen de la web; ese script lee `document.cookie` y obtiene el token del puente, que da acceso al puente completo (ejecución de agentes incluida).

### H2 — Puente: token en la URL y apertura sin token

- `scripts/savia-bridge.py:2043-2045` acepta `?token=` en la query. Un token en la URL queda en historiales, logs de proxy y en `Referer`.
- `scripts/savia-bridge.py:2035-2036` (`if not self.auth_token: return True`) deja pasar sin autenticar. Matiz verificado: con el arranque normal el token siempre existe (`:3807`, `get_or_create_token`); el hueco se abre solo con `--no-auth` (`:3801`) o si `auth_token` queda sin asignar. El puente escucha por defecto en `0.0.0.0` (`:99`), así que `--no-auth` expone el puente a toda la red.
- Clientes de `?token=` hoy: savia-web usa cabecera `Authorization` (`useSSE.ts:35,79`, `MainLayout.vue:21`); la app Android también (`SaviaBridgeService.kt:129`). La única mención es documental y probablemente obsoleta: `projects/savia-web/code-twin/frontend/composables.md:33` (`EventSource ... ?token=`). No hay cliente en el repo que lo necesite; los clientes fuera del repo (enlaces guardados, scripts locales de cada operador) no se pueden inventariar desde aquí. De ahí el periodo de transición del S2.

### H3 — Cúpulas: un error de lectura rota la clave y anula los grants

- `projects/savia-vaults/src/server/grants.ts:53-58`: `key()` envuelve la lectura en `try/catch { /* se crea */ }` y ante cualquier error llama a `this.rotate()`. Un fallo transitorio (permisos, `EBUSY`, `EIO`) genera una clave nueva y todos los grants emitidos dejan de valer, sin registro. Si el fichero existe pero no tiene 32 bytes, también rota, sin dejar rastro.

## Quién lo explota y desde dónde

- H1: quien consiga que el modelo o un fichero abierto en el visor contenga HTML activo (una página web leída por un agente, un fichero de un repo ajeno). No hace falta acceso a la red: basta contenido. Con uso por VPN y operadora única el riesgo directo es bajo; el producto es para todo operador, y en una instalación con varias personas el robo de sesión sí cruza fronteras.
- H2: quien pueda leer historiales, logs de proxy o cabeceras `Referer` (la URL con token se copia y se pega); y, con `--no-auth`, cualquiera que alcance el puerto por VPN o LAN.
- H3: no hay atacante externo; es un fallo de disponibilidad con efecto de seguridad (los grants emitidos se invalidan sin que nadie lo vea y sin forma de distinguirlo de una revocación deliberada).

## Qué cubren ya otras specs (sin duplicar)

- **SE-508** (guard previo de efectos MCP): protege que un agente llame a herramientas MCP con efectos; no toca la web, el puente ni `grants.ts`.
- **SE-510** (guardas sin bloqueos falsos): trata de los hooks de Savia; no toca la autenticación del puente ni el cliente web.
- Conclusión: ninguna cubre H1-H3. Se enlazan por contexto; no se absorbe nada de ellas.

## Puerta de comprensión — qué ve la persona

Solo el S2 cambia cómo se conecta una persona; el S1 cambia dónde se guarda la sesión.

**Antes**: la persona entra en savia-web con la dirección del puente y su token (lo pega en el formulario de acceso). La web lo guarda en una cookie que ella misma escribe y lo manda en cada petición. Si alguien tenía un enlace con `?token=...`, funcionaba y el token quedaba visible en la barra de direcciones.

**Después**: la persona sigue pegando el token una sola vez en el formulario. El puente lo comprueba y, si es válido, le devuelve una sesión que el navegador guarda sin que la página pueda leerla. La persona no ve diferencia en el uso diario. Cambios visibles: (a) un enlace con `?token=` deja de funcionar y devuelve «no autorizado»; durante la transición se admite con un aviso en el registro del puente y una cabecera que lo señala; (b) arrancar el puente sin token con `--no-auth` deja de ser posible salvo en `127.0.0.1` y con el aviso bien visible; (c) las sesiones abiertas antes del cambio piden volver a pegar el token una vez.

**Decisiones abiertas para la operadora** (cambian algo visible):
- Q1. ¿Cuánto dura la transición de `?token=` (propuesta: 14 días con aviso, luego 401)? ¿O corte inmediato, dado que no hay cliente propio que lo use?
- Q2. `--no-auth`: ¿se elimina o se limita a `127.0.0.1`? Propuesta: limitar a `127.0.0.1`; fuera de ahí, el arranque se niega.
- Q3. ¿Se acepta que todas las sesiones web abiertas pidan el token de nuevo una vez (S1)? Propuesta: sí.

## Slices (independientes, en este orden)

### S1 — savia-web: saneado y sesión HttpOnly (tier 3)

Incluye cambios en `auth.ts` y en el puente (endpoint de sesión); por eso depende de acordar con el S2 el contrato de sesión, pero se puede entregar sin retirar nada: la cabecera `Authorization` sigue valiendo.
- Sanear con DOMPurify (o `marked` con renderer que escape HTML crudo) toda salida a `v-html`: `ChatPage.vue:111`, `FileViewer.vue:200`. Un único helper `renderMarkdownSafe` en `src/utils/`; los dos sitios lo usan.
- El puente emite `Set-Cookie: savia_session=...; HttpOnly; Secure; SameSite=Strict; Path=/` tras validar el token en un endpoint de login; la web deja de escribir cookies con JS y deja de guardar el token (`auth.ts:17`, `:27`). El cliente envía `credentials: 'include'`.
- Cabecera `Content-Security-Policy` (sin `unsafe-inline` en scripts) como defensa en profundidad en `index.html`/servidor estático.

AC:
- AC-1.1 Test Vitest: `renderMarkdownSafe('<img src=x onerror="window.__x=1">')` no contiene `onerror`; montado `ChatPage` con ese contenido, `window.__x` queda `undefined`.
- AC-1.2 Idem con `<script>`, `<a href="javascript:...">`, `<svg onload=...>`.
- AC-1.3 Caso positivo: markdown legítimo (títulos, listas, tablas, código, enlaces `https:`) se renderiza igual que antes.
- AC-1.4 Test que recorre `projects/savia-web/src` y falla si hay `v-html`/`innerHTML` que no pase por `renderMarkdownSafe` (lista blanca explícita y vacía al cerrar).
- AC-1.5 Tras el login, `document.cookie` no contiene `savia_session` ni el token (test e2e Playwright); la cookie lleva `HttpOnly`, `Secure` y `SameSite=Strict` (test del puente sobre la cabecera `Set-Cookie`).
- AC-1.6 Negativo: petición al puente con cookie manipulada devuelve 401.

Reversión: revertir la PR; la cabecera `Authorization` no se retiró, así que el cliente anterior sigue funcionando. Riesgo: `Secure` exige HTTPS (el puente ya sirve TLS por defecto); en desarrollo sin TLS la cookie no se envía: documentar `--no-tls` como modo sin sesión por cookie.

### S2 — Puente: token solo en cabecera o sesión, y fallo cerrado (tier 2 por `risk-tier.py`; revisión humana solicitada igualmente por tocar autenticación)

- `scripts/savia-bridge.py:2043-2045`: dejar de leer `?token=`. Transición (según Q1): se acepta con `log(..., "SECURITY")` y cabecera `Deprecation: true`, y a la fecha de corte devuelve 401. Después se borra el código.
- `scripts/savia-bridge.py:2035-2036`: `if not self.auth_token: return True` se sustituye por fallo cerrado: sin token configurado, 401 en toda ruta protegida. `--no-auth` solo se acepta con `--host 127.0.0.1`; con otro host, el arranque termina con error y mensaje claro.
- Actualizar `projects/savia-web/code-twin/frontend/composables.md:33` (documentación obsoleta).

AC:
- AC-2.1 Test: `GET /ruta-protegida?token=<válido>` sin cabecera devuelve 401 (tras el corte); durante la transición devuelve 200 con `Deprecation: true` y una línea SECURITY en el log.
- AC-2.2 Test: `Authorization: Bearer <válido>` sigue devolviendo 200; token inválido, 401 y cuenta en el límite de intentos.
- AC-2.3 Test de arranque: `savia-bridge.py --no-auth --host 0.0.0.0` sale con código distinto de 0 y no abre el puerto.
- AC-2.4 Test de handler: con `auth_token = None` asignado a la clase y sin `--no-auth` local, una petición protegida devuelve 401, no 200.
- AC-2.5 Negativo/límite: `--no-auth --host 127.0.0.1` arranca con el aviso.

Reversión: revertir la PR. Durante la transición, restaurar la aceptación de `?token=` es un cambio de una línea.

### S3 — Cúpulas: rotar solo si no existe (tier 3 por `risk-tier.py`)

- `projects/savia-vaults/src/server/grants.ts:53-58`: capturar el error; si `code === 'ENOENT'`, rotar (primera creación). Cualquier otro error (`EACCES`, `EBUSY`, `EIO`, longitud ≠ 32) lanza un error tipado (`GrantKeyUnavailable`), se registra con el código y **no** rota. Quien llama a `sign`/`verify` falla cerrado.

AC:
- AC-3.1 Test: con `readFileSync` simulado para lanzar `EBUSY` (y `EACCES`), `key()` lanza `GrantKeyUnavailable` y el fichero `token.key` no cambia (mismo contenido tras la llamada).
- AC-3.2 Test: un grant firmado antes del error sigue verificándose después, una vez desaparece el error.
- AC-3.3 Caso positivo: sin `token.key` (ENOENT) se crea y se firma.
- AC-3.4 Límite: `token.key` de 31 bytes lanza error y no rota (corrupción: decide la persona, no el servidor).
- AC-3.5 El error queda registrado con el código del sistema (comprobado en el test).

Reversión: revertir la PR. Efecto en operación: un fichero de clave corrupto ya no se repara solo; hay que borrarlo a mano (`rotate()` explícito, ya existente) y el mensaje de error lo dice.

## Fuera de alcance

- Revocación y rotación periódica de tokens de usuario del puente (`savia-bridge.py:2883-2900`).
- `Access-Control-Allow-Origin: *` en `:2551` (sirve una especificación pública; se revisará por separado).
- Descarga con `?token=` en `projects/savia-vaults/docs/files-http.md:49`: es un enlace firmado con caducidad (diseño distinto); se anota como seguimiento.
- Cualquier cambio de código en esta PR: es solo spec.

## Riesgos

- S1 y S2 comparten el contrato de sesión: si divergen, la web no autentica. Mitigación: el S1 no retira la cabecera `Authorization`.
- Clientes no inventariados con `?token=` (enlaces guardados): mitigados por la transición y el aviso en el registro.
- S3 convierte un autoarreglo silencioso en un fallo visible: es el comportamiento deseado.

## Plan por slices

1. **S1** web (AC-1.1 a 1.6), 2. **S2** puente (AC-2.1 a 2.5), 3. **S3** cúpulas (AC-3.1 a 3.5). Cada una, una PR; sin dependencia de orden en el código salvo el contrato de sesión descrito.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| savia-web (S1) | `projects/savia-web/src/**` | Mismo código; no depende del frontend de agentes |
| Puente (S2) | `scripts/savia-bridge.py` | Mismo script; ningún binding |
| Cúpulas (S3) | `projects/savia-vaults/src/server/grants.ts` | Mismo servidor MCP |

### Verification protocol

- [ ] Funciona en runtime OpenCode: sin cambios de binding, el puente y la web son independientes del frontend
- [ ] Tests Vitest, BATS/pytest y de TS cubren cada caso y su par negativo
- [ ] Ningún hook nuevo; no hay registro en `savia-gates`

### Portability classification

- [x] **PURE_BASH / servicio**: independiente del frontend de agentes (Claude Code u OpenCode).

## Tier de riesgo (`scripts/risk-tier.py`, medido 2026-11-13)

| Slice | Ficheros | Tier |
|---|---|---|
| S1 | `ChatPage.vue`, `auth.ts` | 3 (ruta sensible `auth.ts`) |
| S2 | `scripts/savia-bridge.py` | 2 (revisión humana pedida por la naturaleza del cambio) |
| S3 | `grants.ts` | 3 (ruta sensible) |

Tier 3: revisión humana explícita de cada PR (SE-362).

## Ficheros de esta spec

- Prueba de coherencia: `tests/bats/se528-spec-coherence.bats`.
- Registro: `docs/propuestas/planning.d/SE-528.json` y `docs/propuestas/LOG.d/SE-528-PROPOSED.md`.
- Fragmento de changelog: `CHANGELOG.d/se528-spec-seguridad.md`.

## Aprobación

Pendiente. La operadora decide Q1-Q3 y aprueba la spec; no se implementa nada antes.
