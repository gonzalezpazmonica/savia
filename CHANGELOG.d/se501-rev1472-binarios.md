---
version_bump: patch
section: Security
---

### Security

- SE-501 (#1472, revisión): el escáner de confidencialidad ya no se ciega con un binario en la PR. Con --text el diff traía NUL y GNU grep dejaba de imprimir líneas, así que un PNG antes de un fichero con un término vetado daba CLEAN; ahora se quitan los NUL y todo grep usa -a, también para una línea con un byte inválido.
- SE-501 (#1472, revisión): workflow-hmac-check.py comprueba secrets: inherit en la clave secrets de cada job; el texto de un run: ya no da falso positivo.

