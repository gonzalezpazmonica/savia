---
category: Fixed
spec: SE-315
---
- Unifica la resolución de specs de los gates local y CI, detecta IDs
  ambiguos y permite desambiguación explícita por ruta.
- Corrige G0b para resolver los recibos v2 desde la raíz real del workspace.
- Evita falsos negativos y mensajes `Broken pipe` al auditar specs largas:
  cada criterio consulta directamente el fichero en vez de canalizar una copia
  completa bajo `pipefail`.
