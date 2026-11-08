### Fixed

- Clasificación de ejecución: las rutas temporales y del hogar ajenas al workspace, incluidas rutas hermanas con el mismo prefijo, mantienen el nivel hostil. Las rutas relativas se resuelven desde el directorio de quien llama.
- El diagnóstico de contención sigue emitiendo su informe cuando falla `docker ps`. Pruebas deterministas de clasificación, aislamiento, ausencia de Docker, límites y propagación de errores, recuperadas del trabajo local pendiente S03s (SE-292 / SE-376).
