---
version_bump: minor
section: Security
---

### Security

- soul-continuity: emparejamiento directo soul-pair-v2 con clave soulpk_ de 178,6 bits (CSPRNG, checksum CRC32 en base62), vectores v2 comunes con la app y rechazo de v1 con 426 PAIR_VERSION
- soul pair pinta el QR (codificador propio, modo byte y corrección M) en la terminal y lo guarda con --qr-png en 0600 sin sobrescribir
- Modelo de amenazas y documento para TI con el cálculo de entropía; P2-12 cerrado y P2-14 (agotar la ventana desde la VPN) añadido

