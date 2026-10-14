---
status: PROPOSED
priority: P1
developer_type: agent-team
created: 2026-10-14
author: Savia
phase: B
risk: L4
related_specs: [SE-428, SE-430, SE-431, SE-432, SE-434, SE-435, SE-436]
origin: "Ampliación de alcance de Savia Space: pasar de aplicación que corre dentro de un entorno de escritorio a ser la sesión gráfica completa de Linux, de forma que no haga falta GNOME, KDE ni otro escritorio. Diseño interno en Savia Labs (privado)."
timeline:
  - from: "2026-10-14"
    learned: "2026-10-14"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-439 — Savia Space: sesión gráfica agéntica sobre Linux

## Problema

Hoy Savia Space es un servidor local (`savia-space serve`) con un escritorio infinito que se abre en un navegador (SE-432). Para usarlo hace falta un entorno de escritorio debajo, sea GNOME, KDE u otro. Ese entorno decide cómo se entra en la sesión, dónde viven las ventanas, cómo se cambia de red o de audio, quién manda las notificaciones y qué ve cada aplicación.

Eso tiene tres consecuencias:

- **Doble escritorio.** La persona organiza el trabajo en el plano de Space, pero las aplicaciones que usa (navegador, editor, terminal, ofimática) viven fuera, en otro gestor de ventanas que no sabe nada de proyectos, cúpulas ni niveles de datos.
- **Puntos ciegos de los datos.** El guard de cúpulas (SE-436) y el sandbox (SE-434) controlan lo que hace el motor, pero no lo que pasa en las ventanas. Una captura, el portapapeles o una notificación pueden mover datos N3 sin que Space lo sepa.
- **Agentes sin manos.** Un sistema operativo agéntico necesita que los agentes puedan leer el estado de las aplicaciones y actuar sobre ellas con permiso y con recibo. Dentro de un escritorio ajeno eso solo se puede hacer con trucos frágiles.

## Objetivo

Que Savia Space sea **la sesión gráfica de Linux**: se elige en la pantalla de inicio de sesión (o se arranca desde un TTY) y sustituye por completo al entorno de escritorio. Con Space no hace falta GNOME, KDE, Windows ni macOS para el trabajo diario.

- **Una sola superficie.** Las ventanas de las aplicaciones son objetos del plano infinito, igual que proyectos, sesiones y cúpulas. Se acercan, se agrupan por proyecto y se enlazan.
- **Linux sigue siendo Linux.** Space no sustituye el kernel, systemd, logind, PipeWire, NetworkManager, BlueZ ni Mesa. Sustituye la capa de escritorio: compositor, shell, lanzador, ajustes, notificaciones, bloqueo y portales.
- **Las reglas de datos llegan a las ventanas.** Una ventana abierta desde un proyecto hereda su nivel. Capturas, portapapeles, arrastrar y soltar y notificaciones pasan por las mismas reglas que el motor: N3+ nunca va a la nube, y N2 va a la nube solo con confirmación y recibo.
- **Agentes con permisos explícitos.** Los agentes leen y actúan sobre las aplicaciones por una escalera de vías, de la más estructurada a la más invasiva. Cada peldaño tiene su permiso, su indicador visible y su recibo, y PARA lo corta todo.
- **Fallo seguro.** Si el servidor, el motor o Soul se caen, las ventanas y el trabajo de la persona siguen vivos.

## Arquitectura

### Capas

```
┌────────────────────────────────────────────────────────────────────┐
│ Aplicaciones: Wayland nativas · X11 vía XWayland · Flatpak         │
├────────────────────────────────────────────────────────────────────┤
│ Interfaz de Space (escritorio infinito SE-432, paleta, inspector)  │
│   renderizada como cliente privilegiado del compositor             │
├────────────────────────────────────────────────────────────────────┤
│ space-server · motor (SE-428) · Soul (SE-431) · broker (SE-434)    │
├────────────────────────────────────────────────────────────────────┤
│ space-compositor (nuevo): Wayland, escena, cámara, entrada,        │
│   bloqueo, política de capturas y de entrada sintética             │
│ xdg-desktop-portal-savia (nuevo) · agente polkit · notificaciones  │
├────────────────────────────────────────────────────────────────────┤
│ Sistema base sin cambios: kernel/DRM/KMS · systemd · logind ·      │
│   PipeWire/WirePlumber · NetworkManager · BlueZ · UPower · CUPS    │
└────────────────────────────────────────────────────────────────────┘
```

### Compositor propio en Rust sobre Smithay

El escritorio infinito necesita que las ventanas vivan **en el mismo plano** que los objetos de Space, con la misma cámara, el mismo zoom semántico y los mismos enlaces. Por eso Space no puede ser un plugin de otro gestor de ventanas ni una aplicación a pantalla completa encima de él.

| Opción | Qué es | Pros | Contras | Valoración |
|---|---|---|---|---|
| **A. Compositor propio sobre Smithay** | Crate `space-compositor` en Rust, con Smithay (MIT) para DRM/KMS, libinput, protocolos Wayland y XWayland | Mismo lenguaje y repo que Space; control total de la escena, la cámara y la política de seguridad. Lo validan niri y COSMIC en producción. | Es el componente más grande. Hay que sostener drivers, multi-monitor y accesibilidad. | **Recomendada** |
| B. Kiosco sobre wlroots (tipo cage) | Un compositor mínimo que muestra Space a pantalla completa | Rápido de montar | Las aplicaciones no viven en el plano: vuelve el doble escritorio | Solo como transición |
| C. Plugin o script de KWin o Mutter | Space dentro de KDE o GNOME | Hereda todo el soporte | Sigue necesitando KDE o GNOME, en contra del objetivo | Descartada |

### La escena: un plano, dos renderizadores

- El **compositor** es dueño de la cámara (posición y zoom) y de la escena de ventanas. Cada ventana es un nodo con posición en coordenadas del plano.
- La **interfaz de Space** (PixiJS + DOM, SE-432) se renderiza en un webview fuera de pantalla (WPE WebKit o CEF; decisión S1). Se compone como capa del plano y la cámara se sincroniza con memoria compartida en cada fotograma. Así se conserva todo lo construido en SE-432.
- **Zoom semántico de ventanas**:
  - de lejos, una ficha con icono, título, proyecto y nivel;
  - a media distancia, una miniatura viva a baja frecuencia;
  - de cerca, la superficie real a resolución completa y con entrada.
- **Modo foco**: una ventana pasa a ocupar el monitor, sin bordes, como en un escritorio clásico. Salir del foco la devuelve a su sitio en el plano. Las aplicaciones a pantalla completa (vídeo, juegos) usan scanout directo.
- **Rendimiento**: las ventanas fuera de cámara no se renderizan; los clientes reciben los frame callbacks a frecuencia reducida o nula. La miniatura viva se limita a N ventanas visibles.
- **Más adelante** (fuera de esta spec) se puede portar el render del plano a wgpu nativo y retirar el webview.

### Ventanas como objetos de la ontología

- Nuevo tipo de objeto **Ventana**, con: aplicación (app-id), título, PID y cgroup, proyecto, nivel, origen (lanzada por persona, por agente o por Soul) y monitor.
- **Proyecto de una ventana**:
  - por contexto de lanzamiento: si se abrió desde un proyecto, con un token de activación xdg-activation que lleva el proyecto;
  - si no, por la carpeta de trabajo del proceso bajo `projects/<raíz>`, igual que las sesiones del motor;
  - si no, «sin proyecto», con nivel N1. Una ventana sin proyecto no se expone al móvil ni a los agentes con nivel.
- **Nivel de una ventana**: el máximo de las cúpulas de su proyecto. Si no se puede determinar, el más alto (fallo cerrado, como en el guard de cúpulas).
- Las ventanas de un proyecto aparecen en su tablero y se enlazan, como «observado», con la sesión o el run que las abrió.

### Sesión: cómo arranca Space con el inicio de sesión

- **Entrada desde la pantalla de login existente.** El paquete instala `/usr/share/wayland-sessions/savia-space.desktop`. GDM, SDDM, LightDM o greetd muestran «Savia Space» como sesión. Esto no obliga a quitar el escritorio anterior durante la transición.
- **Entrada desde un TTY.** `savia-space-session` desde el shell de login, para equipos sin gestor de pantalla.
- **Pantalla de login propia** (opcional, fase posterior): un greeter de greetd con la estética de Space.
- **Arranque con systemd de usuario**: `savia-space-session` arranca el compositor, exporta `WAYLAND_DISPLAY` y `XDG_CURRENT_DESKTOP=SaviaSpace` al entorno de systemd y activa `savia-space-session.target`. Ese target es `BindsTo=graphical-session.target` y agrupa:
  - `savia-space-compositor.service`: el único proceso que, si cae, termina la sesión (como en cualquier escritorio Wayland).
  - `savia-space.service`: el servidor que ya se distribuye (SE-435), ahora `PartOf=graphical-session.target` y con `Restart=on-failure`. Si se reinicia, las ventanas siguen vivas.
  - motor y Soul: los gestiona el servidor, como hoy.
  - `xdg-desktop-portal-savia.service`, el agente polkit de Space y XWayland bajo demanda.
  - autoarranque XDG de las aplicaciones de la persona, con `systemd-xdg-autostart-generator`.
- **Sesión segura**: una entrada «Savia Space (sin agentes)» arranca solo el compositor, la interfaz y los ajustes, sin motor ni Soul. Sirve para recuperar el equipo si la configuración de agentes impide trabajar.
- **Salida**: cerrar sesión pide a los clientes que se cierren, espera, cierra el target y vuelve al gestor de pantalla.

### Qué aporta Space en lugar del escritorio

| Lo que hoy da GNOME o KDE | Cómo lo cubre Space | Servicio del sistema que usa |
|---|---|---|
| Gestor de ventanas y compositor | `space-compositor` | DRM/KMS, libinput, logind (seat) |
| Barra, lanzador y menú de aplicaciones | Paleta ⌘K y tablero «Aplicaciones», con las entradas `.desktop` de XDG como objetos | XDG Desktop Entry, MIME |
| Abrir ficheros y enlaces (`xdg-open`) | Asociaciones MIME por defecto, editables en ajustes | `mimeapps.list` |
| Notificaciones | Space implementa `org.freedesktop.Notifications`; cada notificación es un evento en el plano, con nivel heredado de la ventana que la emite | D-Bus de sesión |
| Selector de ficheros, capturas, compartir pantalla, abrir URI y ajustes de apariencia para las aplicaciones | Backend de portal `xdg-desktop-portal-savia`; lo que no implemente, se delega al backend GTK | xdg-desktop-portal, PipeWire |
| Red y VPN | Panel «Red» | NetworkManager por D-Bus |
| Audio | Panel «Sonido» | PipeWire / WirePlumber |
| Bluetooth | Panel «Bluetooth» | BlueZ |
| Pantallas, escala y HiDPI | Panel «Pantallas»; la configuración la aplica el compositor | KMS, wlr-output-management |
| Energía, suspensión, batería y brillo | Panel «Energía» | logind, UPower, power-profiles-daemon |
| Teclado, distribución y métodos de entrada | Panel «Teclado»; text-input-v3 e input-method | xkb, IBus o fcitx5 |
| Bloqueo de pantalla y reposo | Bloqueo propio sobre ext-session-lock-v1; reposo con ext-idle-notify | logind (Lock, PrepareForSleep), PAM |
| Pedir contraseña de administrador | Agente polkit de Space | polkit |
| Llavero de contraseñas | Se usa un Secret Service existente (decisión S2) | org.freedesktop.secrets |
| Gestor de ficheros | Objetos fichero en el plano; Savia Files para lo de proyectos; diálogo del portal para las aplicaciones | — |
| Impresoras | Panel «Impresoras» | CUPS |
| Fecha, hora e idioma | Panel «Sistema» | timedated, localed |
| Actualizaciones | Panel «Sistema», solo aviso y lanzamiento | PackageKit |
| Accesibilidad: lector de pantalla, zoom y alto contraste | Bus AT-SPI y Orca; lista accesible paralela (SE-432); zoom del compositor; temas AA/AAA | AT-SPI |

Los paneles de ajustes son objetos del tablero «Sistema». No se inventa una configuración propia cuando el servicio del sistema ya la guarda: Space es interfaz, no segunda fuente de verdad.

### Aplicaciones

- **Wayland nativas**: xdg-shell, decoraciones del lado del servidor (bordes propios de Space, con proyecto y nivel visibles), fractional-scale, xdg-activation, xdg-foreign, presentation-time, idle-inhibit, tearing-control y drm-lease (realidad virtual).
- **X11**: XWayland bajo demanda, integrado o con xwayland-satellite (decisión S3). Las ventanas X11 tienen las mismas reglas, pero su aislamiento es menor: X11 permite leer otras ventanas X11. Se avisa en su ficha.
- **Flatpak**: funcionan con el portal de Space. Su app-id llega por security-context-v1 y es fiable.
- **Navegadores, videollamadas y compartir pantalla**: la captura solo pasa por el portal (PipeWire) y con el selector de Space. El selector enseña el nivel de lo que se comparte y aplica las reglas de datos.
- **Juegos y aplicaciones a pantalla completa**: scanout directo, inhibición del reposo y sin efectos.

### Cómo interactúan los agentes con las aplicaciones

Los agentes (motor, Soul) **nunca hablan con el compositor directamente**. Lo hacen con tools de Space mediadas por el servidor, que aplica el guard de cúpulas, el broker y los recibos. La escalera, de menos a más invasiva:

1. **Vía estructurada** (por defecto): la API, CLI, D-Bus o MCP propios de la aplicación, dentro del sandbox de SE-434. Ejemplos: `git`, LibreOffice headless, el MCP de un navegador o `gdbus` de un servicio.
2. **Lectura de accesibilidad**: el árbol AT-SPI de una ventana concreta (textos, botones, estados), leído por el broker, filtrado por el nivel de la ventana y con recibo. Sin píxeles.
3. **Captura de una ventana**: imagen de una sola ventana, nunca de la pantalla entera. Se pide por ventana y por sesión de agente, con un indicador visible en el borde mientras dura y con recibo. Una ventana N3+ no se captura para un modelo de nube.
4. **Entrada sintética** (teclado y ratón virtuales): solo con un permiso explícito por sesión y por ventana, que caduca. El borde de la ventana cambia mientras el agente la maneja, y cualquier tecla o movimiento de la persona devuelve el control al momento. PARA lo revoca todo. Nunca se permite en el bloqueo de pantalla, en el agente polkit, en el diálogo de contraseñas ni en ventanas de otro nivel superior al de la sesión.

Reglas comunes:

- Un permiso de un peldaño no concede el siguiente.
- Todo uso queda en el journal con: agente, ventana, peldaño, nivel y hash de lo leído o escrito.
- Soul (SE-431) sigue sin enviar nada privado a la nube. Los eventos del sistema que puede ver (batería, red, ventana abierta o cerrada) son metadatos N1.

### Seguridad

- **Base de confianza.** El compositor y el bloqueo de pantalla pasan a ser la base de confianza de la sesión. El compositor no carga plugins, no ejecuta código de agentes y no habla con modelos. Su IPC con `space-server` es un socket Unix local y autenticado por credenciales del par y huella de imagen (como el broker FS-6b).
- **Protocolos privilegiados.** Solo los clientes propios de Space pueden usar captura (screencopy), entrada virtual, layer-shell y gestión de salidas, identificados por security-context-v1 o por huella de imagen. Una aplicación cualquiera no puede capturar otras ventanas ni teclear en ellas: solo puede hacerlo por el portal y con el consentimiento de la persona.
- **Portapapeles y arrastrar.** Copiar de una ventana N3 y pegar en una ventana de menor nivel avisa y deja un recibo. Pegar o soltar dentro de una sesión del motor pasa por el anillo de contexto (SE-436) con las reglas de N2 y N3+.
- **Bloqueo.** Con la sesión bloqueada no se ejecuta ninguna entrada sintética. Las notificaciones se muestran sin contenido y la captura se niega.
- **Fallo cerrado.** Una ventana de origen desconocido tiene nivel desconocido: no la leen los agentes con modelo de nube.

### Fallos y recuperación

| Qué cae | Qué pasa | Recuperación |
|---|---|---|
| Soul | Nada visible salvo su estado | Lo reinicia el servidor; PARA sigue disponible |
| Motor | Las sesiones del motor se marcan caídas; las ventanas siguen | Lo reinicia el servidor |
| `space-server` | La interfaz muestra «servidor reconectando»; el compositor, las ventanas, el bloqueo y los paneles básicos siguen | systemd lo reinicia (`Restart=on-failure`) |
| Webview de la interfaz | Las ventanas siguen; el compositor muestra una capa mínima propia (lanzador y lista de ventanas) | Se relanza el webview |
| Compositor | Se pierde la sesión gráfica (como en cualquier escritorio Wayland) | El gestor de pantalla vuelve; la sesión segura sigue disponible |

La recuperación del compositor sin perder clientes (como el «handoff» de KWin) queda fuera de alcance.

### Distribución (relación con SE-435)

Los paquetes añaden:

- el fichero de sesión en `wayland-sessions`;
- `savia-space-session`;
- las unidades de usuario;
- la configuración del portal (`savia-space-portals.conf`);
- el agente polkit.

`savia-space setup` comprueba además:

- un seat de logind;
- DRM/KMS con GBM/EGL (Mesa, o NVIDIA ≥ 555 con sincronización explícita);
- XWayland;
- PipeWire y el portal.

Sin GPU utilizable hay un camino de render por software (pixman) que avisa. En macOS y Windows, Space sigue siendo una aplicación: esta spec es solo para Linux.

## Entregas

| Fase | Qué incluye | Criterio de salida |
|---|---|---|
| **F0. Pantalla completa** | Modo kiosco del escritorio de Space dentro del escritorio actual (`--kiosk`), con webview propio en lugar del navegador | Space arranca a pantalla completa sin navegador |
| **F1. Sesión propia** | Compositor en Smithay, sesión en el gestor de pantalla, unidades systemd, ventanas como objetos, lanzador, XWayland, portapapeles, bloqueo, notificaciones y sesión segura | Una jornada de trabajo con navegador, terminal, editor, ficheros y videollamada sin GNOME ni KDE instalados |
| **F2. Sistema** | Paneles de red, sonido, Bluetooth, pantallas, energía, teclado, impresoras y sistema; portal propio; agente polkit; accesibilidad completa | Ninguna tarea habitual de configuración obliga a abrir herramientas de otro escritorio |
| **F3. Agéntico** | Escalera de los cuatro peldaños, ventanas en el tablero del proyecto con nivel, eventos del sistema para Soul y recibos | Un agente completa una tarea que cruza dos aplicaciones con los permisos mínimos y sus recibos |
| F4. Pantalla de login propia | Greeter de greetd | Opcional |

## Criterios de aceptación

### F1

- [ ] AC1 — Tras instalar el paquete, «Savia Space» aparece en GDM, SDDM y greetd. Al elegirla se entra en la sesión y `XDG_CURRENT_DESKTOP=SaviaSpace`.
- [ ] AC2 — `savia-space-session` desde un TTY arranca la sesión completa, y cerrar sesión vuelve al TTY sin procesos de Space vivos.
- [ ] AC3 — La sesión funciona en un sistema sin paquetes de GNOME ni KDE (gnome-shell, plasma-workspace, mutter y kwin ausentes). Se prueba en una VM limpia de Debian o Ubuntu y en Fedora.
- [ ] AC4 — Firefox, Chromium, un terminal, LibreOffice, VS Code (Electron) y una aplicación X11 (por ejemplo, xterm) se abren desde la paleta, aparecen como objetos Ventana en el plano y aceptan teclado y ratón.
- [ ] AC5 — Con 20 ventanas abiertas y 2000 objetos en el plano, el desplazamiento y el zoom se mantienen a ≥ 55 fps en la máquina de referencia, y las ventanas fuera de cámara no reciben frame callbacks.
- [ ] AC6 — Una ventana lanzada desde un proyecto queda en el tablero de ese proyecto, con el nivel máximo de sus cúpulas visible en el borde. Una ventana sin proyecto muestra «sin proyecto».
- [ ] AC7 — Matar `space-server` con SIGKILL no cierra ninguna ventana. systemd lo reinicia y la interfaz se reconecta en < 10 s.
- [ ] AC8 — El bloqueo de pantalla bloquea antes de suspender (logind PrepareForSleep), no muestra contenido de notificaciones y no se puede saltar matando la interfaz ni el servidor.
- [ ] AC9 — Copiar y pegar texto e imágenes entre aplicaciones Wayland y X11 funciona en ambos sentidos.
- [ ] AC10 — La sesión segura arranca sin motor ni Soul y permite abrir aplicaciones y ajustes.

### F2

- [ ] AC11 — Desde Space se conecta a una wifi y a una VPN, se cambia la salida de audio, se empareja un dispositivo Bluetooth, se configuran dos monitores con escalas distintas, se cambia la distribución del teclado y se suspende. Nada de esto requiere herramientas de otro escritorio.
- [ ] AC12 — El selector de ficheros, la captura y compartir pantalla de las aplicaciones van por `xdg-desktop-portal-savia`. Una videollamada en el navegador comparte una ventana elegida en el selector de Space.
- [ ] AC13 — Orca lee la lista accesible y los paneles; toda la sesión se maneja solo con teclado; el alto contraste cumple AAA.
- [ ] AC14 — El agente polkit pide la contraseña para una acción privilegiada (por ejemplo, `pkexec`). Ningún cliente que no sea Space puede capturarla ni teclear en ella.

### F3

- [ ] AC15 — Un agente lee el árbol AT-SPI de una ventana N1 con permiso de peldaño 2, y el journal guarda el recibo. Sin ese permiso, la tool se niega. Si la ventana es N3+ y el modelo es de nube, se niega sin pregunta aunque haya permiso.
- [ ] AC16 — Una captura de una ventana N3+ para un modelo de nube se deniega sin pregunta. Una de N2 pide confirmación y deja recibo.
- [ ] AC17 — Con entrada sintética concedida, el agente escribe en la ventana concedida y en ninguna otra. Una tecla de la persona le quita el control en < 100 ms, y PARA revoca el permiso en < 1 s.
- [ ] AC18 — Ninguna aplicación que no sea Space puede usar screencopy, entrada virtual ni layer-shell (test con un cliente malicioso).
- [ ] AC19 — Pegar en una sesión del motor contenido copiado de una ventana N3 pasa por el anillo de contexto y respeta la regla N3+ para la nube.

## Fuera de alcance

- Distribución propia, imagen ISO o sistema inmutable.
- Sustituir systemd, logind, PipeWire, NetworkManager u otros servicios del sistema.
- macOS y Windows como capa de sistema (allí Space sigue siendo una aplicación).
- Motor de navegador propio.
- Recuperación del compositor sin perder clientes.
- Ver o manejar ventanas del ordenador desde el móvil (SE-430), que necesitaría su propia spec.
- Portar el render del plano a wgpu nativo.

## Riesgos

- **Alcance.** Un compositor completo lleva años en proyectos como niri o COSMIC. Mitigación: Smithay y los servicios estándar del sistema; F1 con lo mínimo de una jornada de trabajo; los paneles en F2.
- **Drivers de GPU.** NVIDIA, sincronización explícita y multi-GPU. Mitigación: matriz de hardware en CI de hardware real y camino por software.
- **Accesibilidad.** Los compositores nuevos suelen romperla. Mitigación: AC13 bloquea F2 y la lista accesible de SE-432 se mantiene como vía completa.
- **Compatibilidad.** Aplicaciones que asumen GNOME o KDE (bandejas de sistema, portales concretos). Mitigación: StatusNotifierItem como objetos; delegar al portal GTK lo que no se implemente.
- **Base de confianza mayor.** El compositor ve todos los píxeles y todas las teclas. Mitigación: proceso separado, sin código de agentes, IPC mínima, fuzzing de la IPC y revisión de seguridad propia (tier 4).
- **Pérdida de sesión por un fallo del compositor.** Mitigación: separar todo lo demás en procesos reiniciables, la sesión segura y, durante la transición, conservar el escritorio anterior instalado.
- **Coste de render.** Webview y compositor a la vez. Mitigación: render bajo demanda, ventanas fuera de cámara congeladas y medición con AC5.

## Decisiones abiertas

| Id | Decisión | Recomendación |
|---|---|---|
| S1 | Webview para la interfaz dentro del compositor: WPE WebKit, CEF o Servo | WPE WebKit: está pensado para embeber y tiene un backend Wayland y uno fuera de pantalla |
| S2 | Llavero: usar el Secret Service instalado (gnome-keyring, KeePassXC u oo7) o empaquetar uno | Usar el que haya; si no hay ninguno, oo7 |
| S3 | XWayland integrado en el compositor o xwayland-satellite | xwayland-satellite en F1, por simplicidad; integrar si hace falta |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `space-compositor`, sesión, portal, paneles | No aplica: componentes de sistema de Space | No aplica: componentes de sistema de Space |
| Tools de la escalera (AT-SPI, captura y entrada sintética) | Tools MCP del servidor MCP de Space | Las mismas tools, servidas por MCP al motor `opencode serve` |
| Guard de ventanas por nivel | Hook PreToolUse ejecutado por el bus de Space | Regla en el plugin `savia-gates` con la misma entrada y la misma salida |

### Verification protocol

- [ ] Funciona en runtime OpenCode: AC15, AC16 y AC17 se ejecutan con el motor `opencode serve` real y un modelo de nube con datos sintéticos N1.
- [ ] El guard de ventanas se prueba con la misma entrada en el hook bash y en `savia-gates`, y ambos dan la misma decisión.
- [ ] Si añade hooks, quedan registrados en el plugin `savia-gates`: el guard de ventanas.

### Portability classification

- [x] **DUAL_BINDING**: el guard de ventanas se implementa a la vez como hook (bus de Space) y como regla de `savia-gates`. Las tools de la escalera se sirven por MCP a cualquier motor. El compositor, la sesión, el portal y los paneles son componentes de sistema sin binding de frontend.
