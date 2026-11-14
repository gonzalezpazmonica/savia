# Instalar Soul Continuidad en tu equipo (SE-490)

Guía para cualquier operador. Soul se instala en tu cuenta de usuario, sin permisos de administración, y no envía datos de trabajo fuera del equipo. Lo que hagas aquí se deshace entero con `soul uninstall --yes` (paso 7).

Los pasos de esta guía están probados en `test/instalar.test.ts` con un `HOME` falso y dobles del llavero y del arranque: el test no toca nada real de la máquina que lo ejecuta. `install.sh` se prueba en `test/install-sh.test.ts` con un espejo falso de nodejs.org, y `soul setup`, `doctor` y `listen` en `test/setup.test.ts` con dobles de la red y de las preguntas.

## Camino corto: dos órdenes

En Linux o macOS, desde la carpeta de Soul (paso 1):

```bash
bash install.sh      # Node.js oficial si hace falta (sin sudo) y la orden «soul» en ~/.local/bin
soul setup           # perfil, VPN, comprobaciones, servicio de tu usuario y emparejar el móvil
```

`soul setup` hace preguntas sencillas y en cada una Intro acepta la respuesta propuesta. Si algo falla, dice qué es y te da la orden exacta para arreglarlo. Después, vuelve a ejecutar `soul setup`: no pisa lo que ya está hecho. La tienes que ejecutar tú en tu terminal. Desde un agente (Claude Code, OpenCode) se rechaza, y sin terminal interactiva no hace nada.

`soul doctor` repite las comprobaciones cuando quieras. Los pasos siguientes explican qué hace cada parte, por si prefieres hacerlo a mano o algo no encaja.

## 0. Requisitos

- **Node.js LTS oficial**, versión 22.6 o posterior. Sin compilar nada: Soul es TypeScript que Node ejecuta directamente. **El Node de Ubuntu y Debian no sirve**, porque viene sin soporte de TypeScript y da `ERR_NO_TYPESCRIPT`. El lanzador lo detecta y busca un Node oficial en `~/.savia/node`, nvm o fnm. Si no hay ninguno, `install.sh` instala el Node.js LTS oficial en `~/.savia/node`, sin sudo y comprobando su SHA-256. En Windows, instálalo desde https://nodejs.org.
- **Almacén de credenciales del sistema**:
  - Linux: Secret Service (GNOME Keyring o KWallet) y la orden `secret-tool`. Si falta, `soul init` y `soul doctor` lo dicen y dan la orden: `sudo apt install libsecret-tools` (Fedora: `sudo dnf install libsecret`; Arch: `sudo pacman -S libsecret`);
  - macOS: el Llavero (viene con el sistema);
  - Windows: Credential Manager (viene con el sistema).

  Sin almacén, Soul no guarda tokens en ningún otro sitio: los adaptadores de API no se activan.
- **Una VPN entre el portátil y el móvil**: la de tu organización o una propia, por ejemplo Tailscale con la misma cuenta en los dos. La app consulta por ella; no hay servidor intermedio.
- Solo para el adaptador `web`: Chrome o Edge ya instalados.

## 1. Obtener Soul

Copia la carpeta `projects/soul-continuity/` del repositorio en tu equipo, por ejemplo en `~/soul-continuity`. Desde ahí:

```bash
bash install.sh
soul help
```

`install.sh` crea `~/.local/bin/soul` y te avisa si esa carpeta no está en tu `PATH`. No pisa una orden `soul` que no sea suya. Con `--download` baja el Node oficial aunque el tuyo ya sirva; `SOUL_NODE_MIRROR` apunta a un espejo de nodejs.org de tu organización. En Windows, crea un `.cmd` con `node %USERPROFILE%\soul-continuity\bin\soul.mjs %*`.

No hace falta `npm install` para usar la CLI ni la API, porque no tienen dependencias de ejecución. Solo el adaptador `web` necesita `playwright-core`, sin descargar navegadores:

```bash
cd ~/soul-continuity/src/web && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --ignore-scripts
```

## 2. Crear tu perfil

`soul setup` lo hace por ti. A mano:

```bash
soul init trabajo --email tu.correo@tu-organizacion.example
soul status
```

`init` crea `config.json` en tu directorio de datos (Linux `~/.local/share/savia/soul-continuity`, macOS `~/Library/Application Support/Savia/soul-continuity`, Windows `%LOCALAPPDATA%\Savia\soul-continuity`). El perfil lleva una referencia opaca y **ninguna fuente ni adaptador activo**. Si detecta tu VPN, porque `tailscale ip -4` responde o hay una interfaz con una IP de `100.64.0.0/10`, fija ahí la escucha y lo dice. Si no la detecta, explica qué hacer. Nunca escucha en `0.0.0.0`. Con `--listen <ip>` eliges tú la dirección. Sin perfil, Soul responde «no sé quién eres».

## 3. Activar adaptadores

Nada está activo por defecto. Para leer una fuente hacen falta tres cosas: el adaptador en `connectors.enabled`, la fuente en tu perfil con propósito y consentimiento, y su sesión (paso 4).

**Camino corto**: una orden escribe las dos primeras. La ejecutas tú, en tu terminal (un agente no puede: el consentimiento lo das tú).

```bash
soul source add github                     # pregunta para qué (Intro acepta lo propuesto), muestra la declaración y pide «s»
soul source add jira --purpose "Mis incidencias" --identity mi-cuenta-id
soul source list                           # fuentes del perfil y su estado
```

Al escribir «s» queda registrado «Activo esta fuente bajo mi responsabilidad» con la fecha y la hora. Con cualquier otra respuesta no se escribe nada. Vale para `github`, `jira`, `azure-devops`, `google-workspace` y `m365-*`; `web` tiene su propio flujo (abajo). `--identity` guarda tu usuario (GitHub, Jira, Azure DevOps) o un correo (Google y Microsoft 365). Si la fuente ya está activa, lo dice y no la duplica. Al terminar te dice la orden del paso siguiente: `soul login <adaptador>`. `soul setup` te ofrece esto al final. Para retirarla, `soul revoke <adaptador>`.

**A mano**, si prefieres editar `config.json` (o necesitas `bases` y `oauth`, que esta orden no toca):

```json
{
  "connectors": {
    "enabled": ["github", "jira", "m365-mail", "m365-calendar"],
    "bases": { "jira": "https://tu-sitio.atlassian.net", "ado": "https://dev.azure.com/tu-organizacion" },
    "oauth": { "microsoft": { "client_id": "<id de la aplicación de tu organización>", "tenant": "<id del inquilino>", "owner": "organization" } }
  },
  "profiles": {
    "trabajo": {
      "operator": { "ref": "op-…", "identities": { "emails": ["tu.correo@tu-organizacion.example"], "github": "tu-usuario" } },
      "sources": [
        { "adapter": "github", "purpose": "Revisiones y tareas asignadas", "consent": { "granted_at": "2026-11-01T09:00:00Z", "statement": "Activo esta fuente bajo mi responsabilidad" } }
      ]
    }
  }
}
```

- `bases`: solo HTTPS. Graph, Google y GitHub tienen la suya por defecto; Jira y Azure DevOps no, porque son de tu sitio u organización. La de Graph y Google solo admite sus hosts oficiales; GitHub Enterprise sí puede ir en el host de tu empresa.
- `oauth`: la aplicación registrada por ti o por tu organización. Soul rechaza las de terceros conocidas. Si tu inquilino exige consentimiento de administración, el adaptador queda `admin_consent_required` y no lee.
- `web`: solo si lo nombras en `enabled`. Su perfil de navegador vive en `<datos>/web/perfil`. Si usaste el adaptador web suelto antes de esta versión, su perfil quedó en el directorio antiguo (`~/.local/share/soul-continuity`, `~/Library/Application Support/SoulContinuity` o `%LOCALAPPDATA%\SoulContinuity`): Soul ya no lo usa ni lo borra; bórralo a mano, porque guarda sesiones. Abre ese perfil con tu navegador y entra a mano en las webs que des a Soul, y solo en esas. En Linux, las cookies de ese perfil se cifran con una clave guardada en tu llavero: sin llavero, el perfil no se abre.
- Para retirar una fuente: `soul revoke <adaptador>` (paso 6).

## 4. Iniciar sesión en cada fuente

```bash
soul login m365-mail                       # muestra un código y una URL; ábrela en tu navegador
soul login google-workspace                # igual, con connectors.oauth.google
soul login github --token-stdin            # pega un token de solo lectura (no se muestra)
soul login jira --token-stdin --days 30    # caducidad para Soul; el token también caduca en su servicio
soul adapters                              # estado de cada fuente
```

Usa tokens de **solo lectura**: un PAT de grano fino en GitHub (Issues y Pull requests en lectura), un token de API de Jira, un PAT de Azure DevOps con `Work Items (Read)` y `Code (Read)`. El token va solo al almacén del sistema; nunca a disco, a la línea de órdenes ni a la salida.

## 5. Emparejar el móvil por la VPN

`soul setup` lo hace por ti. A mano:

1. La escucha va en la dirección de tu equipo **en la VPN**. `soul listen --detect` la busca y la guarda si es una VPN reconocida (Tailscale, NetBird, WireGuard, ZeroTier), y `soul listen 100.x.y.z` la fija. Una 100.x en la conexión del móvil o del router es la red de la operadora, no tu VPN: Soul no la fija sola. Nunca `0.0.0.0` ni `::`: Soul se niega. Sin argumentos, `soul listen` muestra la configurada y la detectada.
2. Arranca la API. Lo mejor es como servicio de tu usuario, para que arranque solo con tu sesión:

   ```bash
   soul autostart install     # o, en una terminal que dejas abierta: soul serve
   ```

   `soul serve` muestra la **huella del certificado (no es la clave)** y te dice cómo seguir: «Para emparejar el móvil, abre otra terminal y ejecuta: soul pair».
3. Abre la ventana de emparejamiento **en otra terminal**:

   ```bash
   soul pair                  # QR, IP, puerto, clave de un solo uso (soulpk_…) y huella corta del certificado
   ```

4. En la app Savia Space, elige el **modo directo** y pulsa **Escanear QR** sobre el QR de la terminal, o pega IP, puerto y clave. La clave empieza por `soulpk_` y sale de `soul pair`; la huella no es la clave. Si la terminal no muestra bien el QR: `soul pair --qr-png qr.png` (fichero 0600; bórralo al terminar). Comprueba que la huella corta que muestra la app es la misma que la de `soul pair`. La clave vale 10 minutos y una sola vez, y admite 3 intentos fallidos. Después hay que volver a ejecutar `soul pair`. Mientras dure la ventana, la clave y el QR son secretos: no compartas capturas.
5. La app nunca envía la clave: Soul y la app se demuestran que la conocen (protocolo `soul-pair-v2`, en `src/contract/CONTRATO.md`). Una app que aún use el código de 10 caracteres (v1) recibe un error que pide actualizarla. Al emparejar, el móvil queda **ligado a su clave**: el token que recibe no sirve desde otro dispositivo. Caduca a los 90 días (`soul pair --days N` para cambiarlo); entonces vuelve a emparejar. Si el certificado de la instalación se renueva, también.
6. No ejecutes `pair` ni `setup` desde un agente (se rechazan).

### Si `serve` no arranca: «la IP configurada no está en ninguna interfaz»

`soul serve` y `soul doctor` comprueban, antes de escuchar, que la IP de la escucha está en tu equipo. Si no está, en vez de un `EADDRNOTAVAIL` verás la causa y la orden del arreglo:

- **NetworkManager gestiona `tailscale0`** y le quita la IPv4 (pasa en Ubuntu). Ejecuta una vez la orden que muestra `soul doctor`, que pide tu contraseña:

  ```bash
  printf '[keyfile]\nunmanaged-devices=interface-name:tailscale0\n' | sudo tee /etc/NetworkManager/conf.d/unmanaged-devices.conf && sudo systemctl reload NetworkManager && sudo systemctl restart tailscaled
  ```

- **La VPN está caída o cambió de IP**: conéctala (`tailscale up`) o guarda la nueva con `soul listen --detect`, y reinicia `serve`.

Si pierdes el móvil: `soul unpair <id> --undo` revoca su token y deshace las correcciones que hizo. `soul corrections --device <id>` las lista antes.

## 6. Uso diario

```bash
soul q1 | soul q2 | soul q4         # qué tengo abierto · qué depende de mí · compromisos con fecha
soul q3 --since 2026-11-01T09:00:00Z
soul mode FOCO --for 2h             # la app lo ve en el siguiente tic de serve
soul stop | soul resume             # detener todo, también tras reiniciar
soul revoke github                  # retira consentimiento, borra su caché y sus tokens
```

Desde Claude Code u OpenCode, `/continuidad` da solo recuentos.

## 7. Desinstalar

```bash
soul autostart uninstall
soul uninstall --yes
```

Borra el directorio de datos de Soul (configuración, libro de correcciones, caché, historial, certificado, dispositivos, perfil web y sus sesiones) y **todas** las credenciales de Soul del almacén del sistema, de todos los adaptadores. Si alguna no se puede borrar, la orden falla y lo dice. Lo que no es de Soul en esa carpeta se conserva. Después, borra la carpeta de `~/soul-continuity` y la orden `~/.local/bin/soul` (y `~/.savia/node` si lo instaló `install.sh` y no lo usas para otra cosa), y el perfil antiguo del adaptador web si lo usaste suelto (paso 3, `web`).

Lo que Soul no puede borrar por ti: la concesión de la aplicación en cada proveedor (Microsoft: Mis aplicaciones; Google: Seguridad > Acceso de terceros; GitHub, Jira y Azure DevOps: sus tokens). Retírala allí.
