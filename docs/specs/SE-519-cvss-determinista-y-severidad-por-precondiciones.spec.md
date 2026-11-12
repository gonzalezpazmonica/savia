---
status: PROPOSED
priority: P2
developer_type: agent-team
created: 2026-11-12
author: Savia
phase: C
risk: L2
human_surface: false
depends_on: []
related_specs: [SE-466]
origin: "Idea aprobada por la operadora el 2026-11-12, a partir de la revisión de los repos públicos de Anthropic (informe en Savia Labs). Contrastada con main 2af8fd6eb."
timeline:
  - from: "2026-11-12"
    learned: "2026-11-12"
    value: "PROPOSED"
---

# SE-519 — CVSS determinista, severidad por precondiciones y búsqueda de variantes

## Problema (leído en main 2af8fd6eb, 2026-11-12; lectura estática)

El agente `pentester` imprime en cada hallazgo `CVSS: {score} ({vector})` (`.claude/agents/pentester.md:82`). Ese número lo calcula el modelo, y los modelos fallan el cálculo: el redondeo hacia arriba de CVSS 3.1, la cadena de `Scope: Changed` y la tabla de 270 macrovectores de CVSS 4.0 no se reproducen de memoria. Un informe con una puntuación mal calculada decide prioridades equivocadas y no se nota.

Lo que existe hoy, comprobado:

1. **No hay calculadora.** Ningún script de `scripts/` calcula CVSS. `grep` de «cvss» en `.claude`, `docs` y `scripts` solo encuentra texto.
2. **Lo que hay es una tabla que no es CVSS.** `.claude/skills/pentesting/SKILL.md` §7 y `.claude/skills/adversarial-security/SKILL.md` §1 llaman «CVSS simplificado» a una suma ponderada (`AV 0.3, AC 0.2, PR 0.2, Impacto 0.3`, ×10). No es la fórmula de FIRST, no usa Scope, User Interaction ni la tríada C/I/A y da números que no coinciden con ningún vector real. Las dos copias pueden divergir.
3. **El formato del hallazgo mezcla dos cosas.** Pide a la vez `Severidad: {CRITICAL|HIGH|MEDIUM|LOW}` y `CVSS: {score} ({vector})` sin decir de cuál deriva la otra.
4. **La severidad ignora las precondiciones.** Un fallo que exige sesión de administrador, una configuración no por defecto o acceso local se puntúa como uno explotable sin autenticación, porque el modelo describe el peor caso. El informe no distingue «explotable hoy desde fuera» de «explotable si ya has perdido otra cosa».
5. **No hay paso de variantes.** Tras un parche, nadie busca el mismo fallo en el resto del código o en versiones hermanas. `pentester` cierra el hallazgo con la prueba y el parche.
6. **SE-466 (OSV) recibe CVSS de terceros**, pero no hay forma de recomputarlo ni de comprobar un vector.

## Qué decide esta spec

- **El modelo elige métricas; un script calcula.** El agente emite el vector (`CVSS:3.1/AV:N/AC:L/...`) y el script devuelve puntuación y severidad. El modelo nunca escribe el número a mano. Un número sin vector, o un vector que no reproduce el número, es un hallazgo inválido.
- **Una sola implementación.** `scripts/cvss.py`, solo biblioteca estándar, sin red. Subcomandos: `score <vector>`, `check <vector> <puntuación>` y `explain <vector>` (métrica a métrica, para que la persona lo audite).
- **3.1 y 4.0 por separado.** La versión se lee del prefijo del vector; un vector sin prefijo o con métricas ausentes o fuera de rango falla cerrado, nunca se completa con valores por defecto. 4.0 usa la tabla oficial de macrovectores de FIRST, incorporada como dato versionado con su origen y licencia anotados; si la licencia no permite redistribuirla, 4.0 queda fuera y se declara (ver D1).
- **Verificada contra vectores publicados.** Fixtures con vectores y puntuaciones de los ejemplos oficiales de FIRST (incluidos los de redondeo y los de Scope Changed). La calculadora no se valida contra su propia salida.
- **Severidad por precondiciones.** Cada hallazgo lleva dos puntuaciones calculadas por el mismo script: `base` (el vector tal como se probó) y `contexto` (el mismo vector con las precondiciones reales del entorno declaradas: privilegios requeridos, interacción, configuración no por defecto, alcance de red). El informe muestra ambas y la causa de la diferencia, y la prioridad usa `contexto`. Las precondiciones son campos del hallazgo con prueba; no se rebaja una severidad por una precondición sin evidencia (misma regla que «no exploit, no report»).
- **Variantes tras un parche.** Un paso nuevo del pipeline, después de la explotación: para cada hallazgo parcheado se registra el patrón causal (fuente, sumidero, control ausente) y se busca el mismo patrón en el resto del alcance autorizado. El resultado es una lista de candidatas con `confidence`, cada una sometida a la misma regla de prueba. Sin prueba, no entra en el informe; se lista aparte como «sin probar».
- **Una tabla, no dos.** Las secciones «CVSS simplificado» de las dos skills se sustituyen por una referencia a `cvss.py`. Lo simplificado deja de llamarse CVSS.
- **No es una autorización.** Nada de esto amplía el alcance del pentest: la búsqueda de variantes respeta el mismo alcance y los mismos permisos (`permissionMode: plan`, L3).

## Decisiones abiertas

| ID | Decisión | Recomendación |
|---|---|---|
| D1 | Licencia y forma de incorporar la tabla de macrovectores de 4.0 | Comprobar los términos del material de FIRST antes de S2. Si no se puede redistribuir, entregar solo 3.1 y dejar 4.0 como `NOT_SUPPORTED` explícito, no como cálculo aproximado |
| D2 | Qué precondiciones cuentan para `contexto` | Cerrada y corta: privilegios, interacción de usuario, configuración no por defecto, alcance de red. Lo demás es comentario, no puntúa |
| D3 | Dónde vive el paso de variantes | Fase nueva 4b del pipeline de `pentester`, no un agente nuevo |

## Slices

| Slice | Entrega | Entrada |
|---|---|---|
| S0 | Solo lectura: inventario de dónde se imprime o cita una puntuación CVSS en agentes, skills y plantillas; resuelve D1 y D2; fija los fixtures oficiales con su origen | Aprobación de S0 |
| S1 | `scripts/cvss.py` con 3.1 (`score`, `check`, `explain`) y su suite BATS contra los fixtures | S0 |
| S2 | CVSS 4.0, o `NOT_SUPPORTED` explícito según D1 | S1 |
| S3 | `pentester.md` y las dos skills: el vector sustituye al número; `base` y `contexto`; fase 4b de variantes; el formato del hallazgo deja claro de cuál deriva la severidad | S1 |
| S4 | Gate: un informe de seguridad con una línea CVSS que `cvss.py check` no reproduce falla la validación del informe | S3 |

Cada slice necesita su propia aprobación.

## Criterios de aceptación

| AC | Criterio | Slice |
|---|---|---|
| AC-1 | El inventario lista cada fichero que imprime o cita CVSS, con ruta y línea, y separa lo que calcula el modelo de lo que viene de un tercero | S0 |
| AC-2 | `cvss.py score` reproduce las puntuaciones de todos los vectores 3.1 publicados por FIRST en los fixtures, incluidos los de redondeo hacia arriba y los de Scope Changed | S1 |
| AC-3 | **Negativo:** vector sin prefijo de versión, con métrica ausente, repetida o con valor fuera de rango → salida distinta de cero y sin puntuación; nunca se asume un valor por defecto | S1 |
| AC-4 | **Negativo:** `check` con una puntuación que no corresponde al vector → fallo con la puntuación correcta en el mensaje | S1 |
| AC-5 | **Límite:** vectores en los bordes de severidad (0.0 None, 3.9/4.0, 6.9/7.0, 8.9/9.0) se clasifican en el lado correcto | S1 |
| AC-6 | Las pruebas fallan si se cambia el redondeo (`roundup`) por un redondeo normal: comprobado por mutación sobre los vectores de redondeo | S1 |
| AC-7 | 4.0: los fixtures oficiales pasan, o `NOT_SUPPORTED` sale con código distinto de cero y motivo. **Negativo:** un vector 4.0 nunca se puntúa con la fórmula 3.1 | S2 |
| AC-8 | Ningún informe nuevo de `pentester` contiene una puntuación sin vector; el formato del hallazgo muestra `base`, `contexto` y la causa de la diferencia | S3 |
| AC-9 | **Negativo:** una precondición declarada sin prueba no rebaja la severidad; `contexto` es igual a `base` en ese caso | S3 |
| AC-10 | La fase 4b produce candidatas con `confidence`; una candidata sin prueba aparece en «sin probar» y no cuenta en el recuento de hallazgos. **Negativo:** la búsqueda no sale del alcance autorizado | S3 |
| AC-11 | Las dos skills dejan de contener la tabla «simplificada» y apuntan a `cvss.py`; un test falla si reaparece | S3 |
| AC-12 | **Negativo:** informe con una línea CVSS que no se reproduce → la validación falla cerrada; sin `cvss.py` disponible, también falla | S4 |

## Fuera de alcance

- Puntuar con EPSS, KEV o SSVC. Se puede añadir después sobre la misma base.
- Recalcular el CVSS que publica un tercero en OSV (SE-466); aquí solo se ofrece `check` para quien lo pida.
- Cambiar permisos o alcance de `pentester`.
- Reescribir los ficheros históricos de informes ya emitidos.

## Riesgo

L2. Código nuevo solo de lectura y cálculo, sin efectos. El riesgo real es doble: una calculadora con un error sistemático que da confianza falsa (por eso AC-2 y AC-6 exigen vectores externos y mutación) y una tabla de 4.0 con licencia dudosa (D1).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| `scripts/cvss.py` | Se invoca con Bash desde el agente | Igual: script sin acoplamiento al frontend |
| Agente `pentester` | `.claude/agents/pentester.md` | Lee desde AGENTS.md generado |
| Skills `pentesting` y `adversarial-security` | `.claude/skills/*/SKILL.md` | Skill registry |
| Gate S4 | Paso de validación de informes en CI | Igual: script en CI |

### Verification protocol

- [ ] Funciona en runtime OpenCode (no solo Claude Code)
- [ ] Tests cubren ambos paths (o marca SKIP justificado)
- [ ] No añade hooks: sin registro en plugin `savia-gates`

### Portability classification

- [x] **PURE_BASH**: lógica en un script sin bindings de frontend (Python estándar), idéntico en cualquier motor. Las ediciones de agente y skills son texto que ambos frontends leen.

## Aprobación

Propuesta (PROPOSED). La idea la aprobó la operadora el 2026-11-12; la spec completa y cada slice esperan su aprobación. Ningún agente la aprueba ni la fusiona.
