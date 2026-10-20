---
status: APPROVED
approved_at: 2026-10-05
approved_by: "operadora, AskUserQuestion 2026-10-05: «Apruebo, empieza por D1»"
delta_approved: "gonzalezpazmonica 2026-10-13, delta «paquetes para terceros al final»"
priority: P1
developer_type: agent-team
created: 2026-10-05
author: Savia
phase: A
risk: L3
related_specs: [SE-428, SE-434]
origin: "Decisión de la operadora del 2026-10-05 (AskUserQuestion, D-MED-7): distribución agnóstica de Savia Space mediante paquetes nativos más `savia-space setup`. Pregunta de partida: «Savia Space tiene que ser agnóstico a la máquina en la que se ejecute. ¿Cómo lo solucionamos, con un instalador?»"
timeline:
  - from: "2026-10-13"
    learned: "2026-10-13"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---

# SE-435 — Savia Space: distribución agnóstica (paquetes nativos y `savia-space setup`)

## Problema

El modo mediado de Space (SE-434) necesita un backend de sandbox que funcione en la máquina. En la mayoría de los sistemas, el bubblewrap del sistema (Linux) o Seatbelt (macOS) bastan sin hacer nada. En Ubuntu 23.10 y posteriores, AppArmor restringe los user namespaces sin privilegios, y `/usr/bin/bwrap` no puede crear el sandbox hasta que el sistema le da un perfil. Ese es un paso **privilegiado**. Space no debe pedir sudo en cada arranque ni confiar en binarios que el usuario pueda reescribir (D-MED-6).

Hoy Space solo se arranca desde el repositorio, con `scripts/run-linux.sh`. No hay forma de instalarlo como cualquier otro programa, y nadie hace el paso privilegiado.

## Objetivo

Que cualquier persona instale Savia Space con el mecanismo normal de su sistema y que el sandbox funcione sin pasos manuales ocultos:

- el paso privilegiado se hace **una sola vez**, en la instalación y con el gestor del sistema;
- quien instala desde git tiene un único comando que detecta lo que falta y lo hace **solo con su confirmación**;
- el doctor siempre dice el estado, la causa y el arreglo.

## Diseño

### 1. Paquetes por plataforma

| Plataforma | Artefacto | Paso privilegiado |
|---|---|---|
| Debian y Ubuntu | `.deb` | Depende de `bubblewrap`. En Ubuntu ≥ 23.10, `postinst` instala y carga el perfil AppArmor oficial `bwrap-userns-restrict` (`/usr/share/apparmor/extra-profiles/`) si no está activo. `postrm` lo retira si lo instaló el paquete |
| Fedora, RHEL y openSUSE | `.rpm` | Depende de `bubblewrap`. Ninguno en la configuración por defecto; si la detección encuentra userns restringido, lo explica `setup` |
| Arch | PKGBUILD (AUR) | Depende de `bubblewrap` |
| macOS | Homebrew (fórmula o cask) | Ninguno: Seatbelt viene con el sistema |
| Windows | Guía y comprobación de WSL2 | Dentro de WSL2 se aplica la fila de Linux que corresponda |

Cada paquete instala el binario `savia-space`, la web compilada, el servicio de usuario opcional (D-SVC-1, que no se activa por defecto) y la documentación. Ninguno escribe en el HOME de quien opera durante la instalación.

### 2. `savia-space setup`

- Detecta la plataforma, el backend de sandbox utilizable (reutiliza la detección de SE-434 S5), el motor (OpenCode), un modelo local con contexto suficiente y las dependencias.
- Para cada carencia muestra la orden exacta para esa distribución y por qué hace falta.
- **Solo ejecuta** lo privilegiado si la persona lo confirma tecleándolo. Nunca lo hace en silencio y nunca en el arranque normal.
- Es idempotente: si ya está todo bien, solo informa.

### 3. Doctor

`savia-space doctor` incluye siempre el estado del backend, la causa si no está LIVE y el arreglo con el paquete o con `setup`.

### 4. Publicación y confianza

- Los artefactos se construyen en CI de forma reproducible, se firman y publican sus checksums.
- La fórmula y el PKGBUILD apuntan a releases firmadas.

## Slices

| Slice | Contenido | Aceptación |
|---|---|---|
| D1 | `savia-space setup` multiplataforma (detección, guía y ejecución confirmada) | AC1–AC3 |
| D2 | `.deb` con dependencia de bubblewrap y perfil AppArmor en postinst y postrm | AC4–AC5 |
| D3 | `.rpm`, PKGBUILD y fórmula de Homebrew | AC6 |
| D4 | CI de releases reproducibles y firmadas, con checksums | AC7 |

**Orden.** D1 va primero: `setup` es requisito del sandbox de SE-434 en Ubuntu 23.10 o posterior.
D2–D4 van al final, cuando el resto de Savia Space esté completo. Lo que ya esté integrado de D2–D4
se conserva y se puede construir en local, pero no se publica en canales públicos (releases,
repositorios de paquetes, fórmulas) hasta entonces.

## Criterios de aceptación

- **AC1:** en una máquina Ubuntu 24.04 con userns restringido, `setup` diagnostica la causa, muestra las dos órdenes del perfil oficial y, tras la confirmación tecleada, deja el sandbox de SE-434 en LIVE (verificado por la sonda).
- **AC2:** sin confirmación, `setup` no ejecuta nada privilegiado. Se prueba con stdin vacío y con una respuesta distinta.
- **AC3:** `setup` es idempotente: en una máquina ya preparada no cambia nada y lo dice.
- **AC4:** instalar el `.deb` en Ubuntu 24.04 limpio deja el sandbox en LIVE sin ningún paso manual. Desinstalarlo retira el perfil si lo instaló el paquete.
- **AC5:** instalar el `.deb` en Debian estable deja el sandbox en LIVE sin perfil, porque no hace falta.
- **AC6:** los paquetes de Fedora, Arch y macOS instalan y arrancan Space. En macOS, el backend Seatbelt pasa la sonda (AC16 de SE-434).
- **AC7:** cada release publica artefactos firmados con checksums. Una compilación reproducible da el mismo hash.

## Fuera de alcance

- Tiendas de aplicaciones (Snap Store, Flathub, Mac App Store). Flatpak queda descartado en D-MED-7 por el sandbox anidado.
- Windows nativo sin WSL2.

## Riesgos

- `postinst` con AppArmor modifica la seguridad del sistema. Se limita al perfil oficial de la distribución, nunca relaja la restricción global y es reversible.
- Mantener varios paquetes cuesta trabajo. Se mitiga con una CI que los construya todos desde la misma fuente.
- Probar macOS y Fedora requiere máquinas o runners de CI de esas plataformas.

## Deltas aprobados

- **Paquetes para terceros al final.** D1 sigue primero; D2–D4 se publican cuando el resto de Savia
  Space esté completo (ver «Orden» en «Slices»). La spec sigue APPROVED.

## Deltas propuestos (pendientes de aprobación de la operadora)

Los deltas de esta sección **no están aprobados**: no modifican `status` ni `delta_approved`, y no
cambian el alcance de D4 hasta que la operadora los apruebe.

- **Releases verificables (D4, AC7 concretado).** Origen: `output/research/20261020-learnings-zero-breach.md`
  (A5, lectura de un proyecto Apache-2.0 que publica builds reproducibles y manifiesto firmado, sin
  ejecutar). Hoy AC7 es una sola frase. El delta la concreta en cinco condiciones verificables:
  1. **Doble build y comparación**: un job de CI construye cada artefacto dos veces y `cmp` exige
     bytes idénticos; si difieren, la release no se publica.
  2. **Manifiesto firmado**: `SHA256SUMS` con firma separada del artefacto y del manifiesto.
  3. **Huella por canal independiente**: la huella completa de la clave se publica en un canal distinto
     del de descarga, y el documento de verificación explica cómo comprobarla.
  4. **Lo que la firma no demuestra**: el documento de verificación dice expresamente que un checksum
     no autentica al publicador y que la firma no prueba que el código sea seguro, solo quién lo
     publicó.
  5. **Custodia de la clave**: la clave privada no vive en el repositorio ni en CI en claro; quién la
     custodia lo decide la operadora (decisión D4-1), no el agente.
  Nuevo criterio propuesto **AC7b**: en un runner limpio, `scripts/verify-release.sh <artefacto>`
  (a crear en D4) descarga el manifiesto, verifica la firma con la huella publicada, compara el
  checksum y sale 0; con un byte alterado del artefacto sale distinto de 0 y nombra la causa.
  Contexto: las releases del repo central hoy solo publican notas y `scripts/update.sh` actualiza con
  `git pull`, así que no hay artefacto que firmar fuera de Space; por eso el delta espera a D2–D4.
  Esfuerzo M a L; riesgo medio por la custodia de clave.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Paquetes y `setup` de Space | No aplica (Space es un binario propio) | Comprueba e instala la dependencia del motor OpenCode |
| Detección de backend | No aplica | La reutiliza de SE-434 S5 |

### Verification protocol

- [ ] Funciona en runtime OpenCode: Space instalado por paquete arranca el motor en modo mediado.
- [ ] Hay tests de las dos rutas: máquina que necesita el paso privilegiado y máquina que no lo necesita.
- [ ] Si añade hooks, quedan registrados en el plugin `savia-gates`. Esta spec no añade ninguno.

### Portability classification

- [x] **PURE_BASH**: el empaquetado y `setup` no dependen del frontend. Distribuyen Space y su motor igual para cualquier frontend.
