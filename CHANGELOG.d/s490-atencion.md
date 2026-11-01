---
version_bump: minor
section: Added
---

### Added

- SE-490: política de atención y registro de demanda en TypeScript (modos, presupuesto, alertas con tope propio, resúmenes), con 228 evals y 62 mutantes, 0 vivos y 0 rotos, que el CI de Soul ejecuta junto a los tests. Los resúmenes no repiten lo ya entregado y cada alerta sobre el tope sale una sola vez dentro de una ejecución (la bandeja no sobrevive a un reinicio); un bloqueo reenviado por el sondeo no se duplica; solo un aviso con regla es alerta; las decisiones vuelven hasta que se responden. Fail-closed: un nivel o canal inválido redacta; la ruta web y cualquier ruta desconocida nunca autentican (un aviso con regla baja a aviso con presupuesto; un permiso se bloquea y nada más de la web pide decisión ni gasta presupuesto); detener y vetar exigen origen autenticado; una alerta vetada o con el contexto vencido se registra; franjas y estado mal formados o con líneas repetidas no se aceptan.
