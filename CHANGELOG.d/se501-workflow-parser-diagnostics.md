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
También rechaza índices calculados y accesos agregados al contexto de secretos;
permite referencias estáticas a otros secretos sin tratar el texto literal como acceso.
El control de auditoría de main rechaza cualquier acceso al contexto de secretos,
incluido el índice literal, las mayúsculas mixtas y la herencia.
Los diagnósticos solo imprimen motivos constantes: ni nombres de jobs ni valores
de acciones procedentes del workflow inspeccionado llegan al log.

Los lectores Python comprueban la frescura aun cuando los derivados ya
existen. Si esa comprobación falla, no usan datos viejos para dar un verde;
la procedencia opcional de ablation queda UNKNOWN.
