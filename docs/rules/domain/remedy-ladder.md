---
context_tier: L2
token_budget: 650
---

# Escalera de remedios

> Leer cuando: vas a añadir una regla, hook, skill o script para que un fallo no se repita, o cuando revisas en una poda si algo sobra.

Cada fallo se arregla con el escalón **más barato** que lo resuelve. Una regla nueva tiene que explicar en su PR por qué no basta el escalón anterior.

| Escalón | Cuándo | Coste |
|---|---|---|
| 0. Nada | Ha pasado una sola vez | Ninguno |
| 1. Una línea en la skill o regla que ya aplica | Error de secuencia corriente | Tokens de una línea en cada carga |
| 2. Script determinista (`scripts/`) | El modelo repite a mano una extracción, conversión o comprobación | Mantenimiento del script, cero tokens |
| 3. Skill a demanda | Procedimiento de varios pasos con un disparador claro (se nombra en una línea siempre visible) | Tokens solo cuando se usa |
| 4. Hook o gate | Hay evidencia repetida de que la prosa se ignora, o saltársela cuesta mucho (seguridad, privacidad, gobierno) | Latencia en cada llamada y riesgo de bloquear trabajo válido |

## Reglas

- El escalón 4 no debe impedir terminar un trabajo válido. Si un hook bloquea algo legítimo, se corrige el hook, no se añade una excepción en prosa.
- Ante un error de herramienta, primero se clasifica: entrada mala, tiempo agotado, capacidad que falta, permiso o salida sin leer. Después, un plan alternativo acotado con condición de parada. Nunca se repite a ciegas (ver `autonomous-safety.md`, fail-safe).
- La Regla 6 («repetición 2+ → skill») es el escalón 3. Antes de crear la skill, comprobar si un script (escalón 2) lo resuelve con menos.
- Las lecciones que justifican subir de escalón se guardan como propuestas de aprendizaje con `--when` (cuándo aplica), evidencia y `--confidence` (`scripts/learning-proposal.sh`).

## Origen

Adaptado de la guía del editor de harness de google-research/harness2 (Apache-2.0), que elige el componente más barato capaz de arreglar el fallo observado en la trayectoria.
