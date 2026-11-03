---
version_bump: minor
section: Added
---

### Added

- Soul Continuidad: instalación en un paso. `install.sh` instala Node.js LTS oficial en ~/.savia/node sin sudo (SHA-256 verificado) y crea la orden `soul` (solo descargas HTTPS, rutas escapadas); `soul setup` encadena perfil, escucha en la VPN, comprobaciones, servicio de usuario y emparejamiento.
- Soul Continuidad: el lanzador detecta un Node sin TypeScript (ERR_NO_TYPESCRIPT, el de Ubuntu) y usa uno oficial de ~/.savia/node, nvm o fnm, o explica la solución.
- Soul Continuidad: `soul init` y `soul listen --detect` fijan la IP de una VPN reconocida (`tailscale ip -4` o una interfaz de VPN de malla), nunca 0.0.0.0 ni una 100.64/10 de la WAN o el módem (CGNAT de la operadora), que solo se propone; `soul setup` abre `pair` solo si responde el TLS con la huella de la instalación; `soul doctor` y `soul serve` diagnostican una IP ausente (NetworkManager y tailscale0, con la orden de unmanaged-devices) y la falta de secret-tool.
- Soul Continuidad: `soul serve` etiqueta la huella como «huella del certificado (no es la clave)» y explica cómo emparejar con `soul pair`.

