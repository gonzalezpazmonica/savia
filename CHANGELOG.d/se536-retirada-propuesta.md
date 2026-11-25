---
version_bump: patch
section: Added
---

### Added

- SE-536 (PROPOSED): retirada del ranking de skills y de la realimentación automática de memoria. Ambos tienen fallos reproducidos (primera entrada perdida, ventana de fechas que no filtra, puntuación que no distingue una skill rota, éxito o fallo decidido por palabras sueltas) y ningún uso: el ranking nunca ha recibido un dato y la realimentación está apagada desde septiembre. Dos slices de retirada. Solo spec; ningún guion ni hook cambia todavía.
