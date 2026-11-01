# Instalar Soul Continuidad en tu equipo (SE-490)

Guía para cualquier operador. Soul se instala en tu cuenta de usuario, sin permisos de administración, y no envía datos de trabajo fuera del equipo. Lo que hagas aquí se deshace entero con `soul uninstall --yes` (paso 7).

Los pasos de esta guía están probados en `test/instalar.test.ts` con un `HOME` falso y dobles del llavero y del arranque: el test no toca nada real de la máquina que lo ejecuta.

## 0. Requisitos

- **Node.js LTS oficial**, versión 22.6 o posterior (`node --version`). Sin compilar nada: Soul es TypeScript que Node ejecuta directamente.
- **Almacén de credenciales del sistema**:
  - Linux: Secret Service (GNOME Keyring o KWallet) y la orden `secret-tool` (paquete `libsecret-tools` o equivalente);
  - macOS: el Llavero (viene con el sistema);
  - Windows: Credential Manager (viene con el sistema).

  Sin almacén, Soul no guarda tokens en ningún otro sitio: los adaptadores de API no se activan.
- **La VPN de tu organización** (o una VPN propia entre el portátil y el móvil). La app consulta por ella; no hay servidor intermedio.
- Solo para el adaptador `web`: Chrome o Edge ya instalados.

## 1. Obtener Soul

Copia la carpeta `projects/soul-continuity/` del repositorio en tu equipo, por ejemplo en `~/soul-continuity`. Desde ahí:

```bash
alias soul="node $HOME/soul-continuity/bin/soul.mjs"   # en Windows: doskey o un .cmd con la misma orden
soul help
```

No hace falta `npm install` para usar la CLI ni la API: no tienen dependencias de ejecución. Solo el adaptador `web` necesita `playwright-core`, sin descargar navegadores:

```bash
cd ~/soul-continuity/src/web && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --ignore-scripts
```

## 2. Crear tu perfil

```bash
soul init trabajo --email tu.correo@tu-organizacion.example
soul status
```

`init` crea `config.json` en tu directorio de datos (Linux `~/.local/share/savia/soul-continuity`, macOS `~/Library/Application Support/Savia/soul-continuity`, Windows `%LOCALAPPDATA%\Savia\soul-continuity`). El perfil lleva una referencia opaca, **ninguna fuente, ningún adaptador activo y ninguna dirección de escucha**. Sin perfil, Soul responde «no sé quién eres».

## 3. Activar adaptadores

Nada está activo por defecto. Para leer una fuente hacen falta tres cosas en `config.json`, y las tres las escribes tú:

1. el adaptador en `connectors.enabled`;
2. la fuente en tu perfil, con propósito y consentimiento;
3. su sesión (paso 4).

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

- `bases`: solo HTTPS. Graph, Google y GitHub tienen la suya por defecto; Jira y Azure DevOps no, porque son de tu sitio u organización.
- `oauth`: la aplicación registrada por ti o por tu organización. Soul rechaza las de terceros conocidas. Si tu inquilino exige consentimiento de administración, el adaptador queda `admin_consent_required` y no lee.
- `web`: solo si lo nombras en `enabled`. Su perfil de navegador vive en `<datos>/web/perfil`. Abre ese perfil con tu navegador y entra a mano en las webs que des a Soul, y solo en esas. En Linux, las cookies de ese perfil se cifran con una clave guardada en tu llavero: sin llavero, el perfil no se abre.
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

1. Pon en `api.listen` la dirección de tu equipo **en la VPN** (por ejemplo la `100.x.y.z` de tu cliente VPN). Nunca `0.0.0.0` ni `::`: Soul se niega.
2. Arranca la API y abre una ventana de emparejamiento:

   ```bash
   soul serve                 # o: soul autostart install, para que arranque con tu sesión
   soul pair                  # QR, IP, puerto, clave de un solo uso (soulpk_…) y huella corta del certificado
   ```

3. En la app Savia Space, elige el **modo directo** y pulsa **Escanear QR** sobre el QR de la terminal, o pega IP, puerto y clave. Si la terminal no muestra bien el QR: `soul pair --qr-png qr.png` (fichero 0600; bórralo al terminar). Comprueba que la huella corta que muestra la app es la misma que la de `soul pair`. La clave vale 10 minutos, una sola vez y admite 3 intentos fallidos; después hay que volver a ejecutar `soul pair`. Mientras dure la ventana, la clave y el QR son secretos: no compartas capturas.
4. La app nunca envía la clave: Soul y la app se demuestran que la conocen (protocolo `soul-pair-v2`, en `src/contract/CONTRATO.md`). Una app que aún use el código de 10 caracteres (v1) recibe un error que pide actualizarla. Al emparejar, el móvil queda **ligado a su clave**: el token que recibe no sirve desde otro dispositivo. Caduca a los 90 días (`soul pair --days N` para cambiarlo); entonces vuelve a emparejar. Si el certificado de la instalación se renueva, también.
5. No ejecutes `pair` desde un agente (se rechaza).

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

Borra el directorio de datos de Soul (configuración, libro de correcciones, caché, historial, certificado, dispositivos, perfil web y sus sesiones) y **todas** las credenciales de Soul del almacén del sistema, de todos los adaptadores. Si alguna no se puede borrar, la orden falla y lo dice. Lo que no es de Soul en esa carpeta se conserva. Después, borra la carpeta de `~/soul-continuity` y el alias.

Lo que Soul no puede borrar por ti: la concesión de la aplicación en cada proveedor (Microsoft: Mis aplicaciones; Google: Seguridad > Acceso de terceros; GitHub, Jira y Azure DevOps: sus tokens). Retírala allí.
