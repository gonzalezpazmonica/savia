---
version_bump: patch
section: Security
---

### Security

- SE-528 S1: savia-web sanea todo el markdown pintado con v-html (chat y visor de ficheros) por un único punto (renderSafeMarkdown: escapa HTML crudo, filtra esquemas de URL, sin onclick en línea) y el servidor estático envía Content-Security-Policy sin unsafe-inline en scripts; el texto que sigue a un tag en línea <pre>/<code>/<kbd>/<script> también sale escapado (cierra un salto del saneador por el estado inRawBlock de marked)
