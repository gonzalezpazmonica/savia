---
version_bump: patch
section: Fixed
---

### Fixed

- Savia Shield (SE-453 S6): la lista «parece código» que rebaja un bloqueo a aviso en ficheros de código casa ahora con la entidad entera, solo con tipos de nombre y sin claves de secreto. Antes bastaba que una entidad empezara por `Microsoft`, `from `, `HTTP`, `github`…, terminara en `:8080` o contuviera `timeout=` para ocultar un dato real. Lógica en `scripts/lib/sh01-code-allowlist.sh`; tests cruzados de Claude y Codex.
- La misma lista distingue mayúsculas y ya no deja sufijos abiertos tras palabras cortas: apellidos como «Restrepo», «Apiano» o «Httpson», «From Garcia», «Amazon.Garcia» o un `dni=12345` dejaban de bloquearse por casar con `REST…`, `API…`, `HTTP…`, `from X`, `Amazon.X` o `X=número`. Ahora las siglas solo admiten un sufijo técnico de lista cerrada (`HTTPError`, `APIKey`), las palabras clave solo un identificador de código, los espacios de nombres solo segmentos de código o de lista cerrada y `clave=número` solo claves de lista cerrada (`tests/test-se453-s6-sh01-prefijo.bats`).
- Tests de mutación (`tests/test-se453-s6-mutantes.bats`): matan los supervivientes S3, S4, S5, S7, S8 y S14 de la auditoría del 2026-11-27 (hook sin la librería, claves de secreto una a una, tipos NER con subcadena, loopback con sufijo, entidad multilínea).
