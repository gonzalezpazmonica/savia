---
version_bump: patch
section: Security
---

### Security

- Bridge: el mensaje y el system prompt del cliente ya no pueden inyectar opciones en claude, codex u opencode (CodeQL #20); CORS valida el origen completo, acepta solo loopback, RFC 1918 y 100.64/10, y reconstruye la cabecera sin caracteres del cliente (#11 y #105, la misma regla reabierta sobre la primera versión del arreglo).
- Shield daemon: filtro de argumentos sin backtracking cuadrático (#58, 9 s → 0,02 s con 20 000 caracteres).
- Voz: el fallback edge-tts escribe en un directorio privado en lugar de usar tempfile.mktemp (#54, #55), y un texto que empiece por `-` ya no se interpreta como opción de edge-tts.
- sp-recordings y teams_attachments eligen la pestaña CDP por hostname, no por subcadena de URL (#50, #51); se aceptan también las nubes soberanas (teams.microsoft.us, sharepoint.us/.cn), y el extractor de adjuntos reconoce esas mismas URLs de SharePoint. El dominio desnudo `sharepoint.com` deja de seleccionarse.
- ZeroClaw: el asistente de red ya no muestra los dos últimos caracteres de la contraseña WiFi (#22).
- SaviaVaults A2A: los errores 500 responden de forma genérica y el detalle queda en el log local, con CR/LF escapados (#1).

