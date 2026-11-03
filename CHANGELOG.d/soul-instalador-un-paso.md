---
version_bump: minor
section: Added
---

### Added

- Soul Continuidad: instalación en un paso. `install.sh` instala Node.js LTS oficial en ~/.savia/node sin sudo (SHA-256 verificado) y crea la orden `soul`; `soul setup` encadena perfil, escucha en la VPN, comprobaciones, servicio de usuario y emparejamiento.
- Soul Continuidad: el lanzador detecta un Node sin TypeScript (ERR_NO_TYPESCRIPT, el de Ubuntu) y usa uno oficial de ~/.savia/node, nvm o fnm, o explica la solución.
- Soul Continuidad: `soul init` y `soul listen --detect` fijan la IP de la VPN (Tailscale o 100.64/10), nunca 0.0.0.0; `soul doctor` y `soul serve` diagnostican una IP ausente (NetworkManager y tailscale0, con la orden de unmanaged-devices) y la falta de secret-tool.
- Soul Continuidad: `soul serve` etiqueta la huella como «huella del certificado (no es la clave)» y explica cómo emparejar con `soul pair`.

