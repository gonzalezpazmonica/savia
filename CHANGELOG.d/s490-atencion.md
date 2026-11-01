---
version_bump: minor
section: Added
---

### Added

- SE-490: política de atención y registro de demanda en TypeScript (modos, presupuesto, alertas con tope propio, resúmenes), con 228 evals y 50 mutantes, 0 vivos. Fail-closed: un nivel o canal inválido redacta; la ruta web nunca autentica (sus reglas de alerta bajan a aviso y nada de ella pide decisión ni gasta presupuesto); detener y vetar exigen origen autenticado; una alerta vetada o con el contexto vencido se registra; franjas y estado mal formados no se aceptan.
