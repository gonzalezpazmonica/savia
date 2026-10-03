---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-02
author: Savia
phase: A
risk: L3
related_specs: [SE-428, SE-429]
origin: "Mandato de la operadora 2026-10-02: migrar Savia Mobile a un proyecto nuevo diseñado para consumir Savia Space por red local, VPN o internet, y adaptar su funcionalidad a Savia Space"
resource: https://developer.android.com/privacy-and-security/keystore
---

# SE-430 — Savia Space Mobile: cliente Android de Savia Space

## Problema

La app actual (`savia-mobile-android`) habla con Savia Bridge. Usa un token, un certificado
autofirmado sin fijar y actualizaciones de APK servidas por el propio Bridge. La mitad de sus
pantallas (Kanban, TimeLog, Git, equipo, comandos) son funciones del workspace de gestión, no de
Savia Space. No puede consumir Space ni aprobar desde el móvil el trabajo de los agentes.

## Objetivo

Una app nueva, **Savia Space Mobile**, que es solo cliente de Space. Lo consume por red local,
VPN o internet (vía VPN mientras internet directo esté bloqueado). Su función distintiva es ser
el **dispositivo de aprobación**: un agente pide y la persona ve exactamente qué se hará y lo
aprueba con biometría.

## Diseño

1. **Proyecto.**
   - Proyecto Gradle nuevo (Kotlin, Compose, Hilt, OkHttp, Room, Tink), propuesto dentro del
     monorepo de Space para compartir contratos generados de la misma OpenAPI (SE-429).
   - Se copia y revisa de la app antigua: tema, navegación, almacenamiento cifrado e
     infraestructura de tests.
   - **No se copia nada del canal del Bridge**: ni su cliente, ni la confianza en certificados
     sin fijar, ni la instalación de APK.
2. **Funcionalidad.**
   - **Inicio**: sesiones recientes, ejecuciones en curso, aprobaciones pendientes y salud.
   - **Sesión**: fuentes, tarea, inspector con el hash comprobado en el propio teléfono,
     streaming, citas, validación, parar y compartir el borrador marcado.
   - **Bandeja de aprobaciones y permisos**: peticiones de terceros, de agentes (SE-428) y
     envolventes delegadas.
   - **Fuentes**: búsqueda y captura en las cúpulas, sin crear notas (Space es de solo lectura
     sobre las cúpulas).
   - **Instancias**: varias, con varios endpoints cada una.
   - **Lo que no tiene equivalente en Space** (gestión de proyectos del Bridge) queda en la app
     antigua congelada.
3. **Conectividad.**
   - Space escucha en interfaces de red declaradas una a una, nunca en todas por defecto. Solo
     sirve la API con bearer; la interfaz web sigue en loopback.
   - TLS 1.3 con una CA propia por instancia. El teléfono fija la clave pública del certificado
     (SPKI) al emparejar. Sin coincidencia de pin no hay conexión, aunque el certificado sea de
     una CA pública.
   - **Red local**: descubrimiento mDNS solo mientras está abierta la ventana de emparejamiento.
   - **VPN** (WireGuard o Tailscale): el camino remoto recomendado.
   - **Internet directo**: bloqueado hasta tener un modelo de amenazas remoto, DPoP obligatorio y
     un emisor de identidad externo.
4. **Emparejamiento.**
   - La persona, en la interfaz web local, elige permisos, proyectos y nivel. Space muestra un QR
     de un solo uso y 5 minutos de validez, con la identidad de la instancia, sus endpoints, el
     pin y un código de 128 bits.
   - El teléfono genera dos claves no exportables en Android Keystore (StrongBox si existe):
     - una para autenticarse y para DPoP;
     - otra para aprobar, que exige biometría fuerte (clase 3) en cada uso, sin admitir el PIN
       o el patrón del dispositivo, y que queda invalidada si se añade o se borra una huella
       (`setInvalidatedByBiometricEnrollment(true)`); entonces hay que volver a emparejar.
   - **Confirmación activa**: tras el registro, el dispositivo queda pendiente. La interfaz web y
     el teléfono muestran a la vez su nombre y una huella corta de su clave de autenticación
     (thumbprint RFC 7638 truncado, en grupos legibles). Solo cuando la persona confirma en la web
     que coinciden, el dispositivo se activa y puede pedir tokens. Sin confirmación dentro de la
     ventana de 5 minutos, o con rechazo, el registro se descarta y el código queda consumido.
5. **Tokens.**
   - `client_credentials` con `private_key_jwt` produce tokens de 300 s ligados por DPoP.
   - Revocar el dispositivo desde la web lo corta en la siguiente petición. Al recibir esa
     respuesta, el teléfono borra su caché y sus claves.
6. **Aprobar desde el teléfono.**
   - Al abrir una petición, Space prepara de nuevo y el teléfono muestra y comprueba los bytes.
     Si una fuente cambió desde la petición, se avisa.
   - Aprobar firma, tras biometría, un JWS con los hashes, un nonce del servidor y caducidad de
     60 s.
   - Cuenta como aprobación de persona: vio los bytes y la biometría prueba presencia en ese
     dispositivo, no identidad legal.
   - **Delegación acotada en el teléfono**: la clave de autenticación (que no exige biometría)
     solo aprueba riesgo bajo. Riesgo medio o alto exige siempre la clave de aprobación con
     biometría. El riesgo lo calcula Space de forma determinista (SE-429) y viaja en la
     petición; la app lo muestra pero no puede bajarlo.
7. **Datos en el teléfono.**
   - Caché cifrada solo hasta el nivel del dispositivo (N2 por defecto); N3 o superior nunca se
     guarda.
   - Sin copias de seguridad del sistema.
   - Capturas de pantalla bloqueadas en el inspector y en la bandeja.
   - Nada se encola sin conexión.
8. **Notificaciones.**
   - Por defecto, ninguna push. La app consulta al abrirse y un trabajo periódico (≥ 15 min)
     cuenta las pendientes.
   - Opcional: UnifiedPush con servidor propio y sin contenido.
   - Nunca notificaciones con contenido a través de terceros.
9. **Distribución.**
   - APK firmado en GitHub Releases (y opcionalmente un repositorio F-Droid propio).
   - Space no sirve APKs.
   - La app comprueba la compatibilidad de protocolo con la instancia antes de operar.

## Criterios de aceptación

- **AC1**: un QR caducado o ya usado no empareja.
- **AC2**: un certificado con otra clave en la misma dirección se rechaza y se muestra.
- **AC3**: un token capturado y usado desde otra máquina se rechaza (DPoP).
- **AC4**: sin biometría no se puede aprobar.
- **AC5**: si una fuente cambió, el teléfono avisa y la aprobación ata los hashes nuevos.
- **AC6**: un dispositivo revocado borra su caché al recibir la siguiente respuesta.
- **AC7**: un dispositivo N2 no ve, no guarda y no notifica nada N3.
- **AC8**: el mismo vector de canonicalización JSON da el mismo hash en Rust, TypeScript y
  Kotlin.
- **AC9**: con la delegación acotada del dispositivo, aprobar una tarea de agente con edición
  (riesgo medio) con la clave de autenticación falla con `STEP_UP_REQUIRED` y no crea la
  ejecución (test de servidor y test instrumentado de la app).
- **AC10**: tras añadir una huella nueva en el sistema, la clave de aprobación queda invalidada:
  la app no firma y pide volver a emparejar.
- **AC11**: con solo PIN o patrón, la clave de aprobación no firma.
- **AC12**: un dispositivo registrado con un QR válido pero sin confirmación en la web no obtiene
  tokens (401) y desaparece al cerrarse la ventana; con confirmación, se activa.
- **AC13**: la huella corta que muestra la web (calculada por el servidor) y la que muestra el
  teléfono coinciden para la misma clave, con un vector de test compartido; dos registros en
  carrera con el mismo QR producen uno solo.

## Entregas

Calendario único de SE-428: M1–M3 entran en Space **0.4**, junto con la interoperabilidad
(SE-429). M4 va después de M3.

- **M1**: app con sesión de lectura en loopback de desarrollo.
- **M2**: red local y VPN con TLS fijado, emparejamiento por QR y sesión completa.
- **M3**: bandeja de aprobaciones y permisos con biometría.
- **M4**: VPN documentada como acceso remoto y congelación de la app antigua.

## Decisiones pendientes

- **D1**: app dentro del monorepo de Space (propuesto) o proyecto separado.
- **D2**: congelar la app antigua para las funciones del Bridge (propuesto) o incluir un módulo
  heredado.
- **D3**: sin push (propuesto) o UnifiedPush propio.
- **D4**: interfaz web solo en loopback y API con bearer en red (propuesto).

## OpenCode Implementation Plan

### Bindings touched

Ninguno: app Android cliente de una API HTTP; no añade hooks, agentes ni skills al workspace.

### Verification protocol

- [ ] Tests unitarios Kotlin y vectores de canonicalización compartidos con Rust y TypeScript.
- [ ] Escenarios AC1–AC13 contra una instancia de Space de prueba.

### Portability classification

- [x] **PURE_BASH** (equivalente: cliente independiente del frontend de agentes)
