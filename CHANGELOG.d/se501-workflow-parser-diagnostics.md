---
type: fix
scope: ci
spec: SE-501
---

El verificador de workflows mantiene el fallo cerrado ante YAML inválido y
ficheros ilegibles, pero evita imprimir excepciones que puedan contener líneas
del fichero inspeccionado. Una regresión comprueba el código de salida y que
el contenido de la entrada no se filtre al diagnóstico.

El detector rechaza también referencias a la clave HMAC con diferencias de
mayúsculas y mediante índice, igual que las referencias válidas de Actions.
