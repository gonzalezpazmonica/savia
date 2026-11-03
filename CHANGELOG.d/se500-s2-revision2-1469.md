---
version_bump: patch
section: Security
---

### Security

- merge-sprint (SE-500 S2, segunda revisión #1469): un derivado, registro o directorio que los contiene convertido en enlace simbólico en la rama ya no permite escribir fuera del worktree (equivalencia y resync lo rechazan antes de escribir; el resolutor abre --out con O_NOFOLLOW); la auditoría trata un escaneo incompleto como bloqueo; los derivados no equivalentes sin otro cambio se aparcan sin consultar al juez; plan muestra los refs y distingue «sin revisión» de «cabeza no equivalente»; un fallo al montar la raíz congelada ya no deja restos.
