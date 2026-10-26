# Fuentes públicas

Consultadas el 2026-10-23 salvo indicación. «Fecha» es la que muestra la página; `n/d` = no figura. Las claves (A1, OA1…) se usan en las demás referencias.
Lectura: **literal** = texto de la página; **resumen** = pasó por el resumen de un modelo de lectura (las cifras así obtenidas se marcan).

## Anthropic

| Clave | Fuente | Fecha | Uso en la skill | Evidencia |
|---|---|---|---|---|
| A1 | Building effective agents. https://www.anthropic.com/engineering/building-effective-agents | 2024-12-19 | Empezar simple; flujos frente a agentes | O |
| A2 | Effective harnesses for long-running agents. https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents | 2025-11-26 | Inicializadora, progreso, lista de tareas | O |
| A3 | Harness design for long-running application development. https://www.anthropic.com/research/harness-design-long-running-apps | 2026-03-24 | Generador y evaluador separados; retirar estructura al mejorar el modelo; 20 min y 9 USD frente a 6 h y 200 USD (una ejecución) | M-int |
| A4 | Effective context engineering for AI agents. https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents | 2025-09-29 | Contexto finito, compactación, subagentes con resumen | O |
| A5 | Scaling Managed Agents. https://www.anthropic.com/engineering/managed-agents | 2026-04-08 | Sesión como registro de solo añadir; credenciales fuera del sandbox | O; M parcial en latencia |
| A6 | How we built our multi-agent research system. https://www.anthropic.com/engineering/multi-agent-research-system | 2025-06-13 | ≈15x tokens de un chat; tokens explican el 80 % de la varianza en BrowseComp; −40 % de tiempo con mejores descripciones | M-int, no reproducible |
| A7 | Writing effective tools for agents. https://www.anthropic.com/engineering/writing-tools-for-agents | 2025-09-11 | Diseño de herramientas | O |
| A8 | Demystifying evals for AI agents. https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents | 2026-01-09 | 20-50 tareas; pass@k y pass^k | O |
| A9 | Claude Agent SDK: subagents, hooks, sessions, agent loop, permissions. https://code.claude.com/docs/en/agent-sdk/subagents.md, `/hooks.md`, `/sessions.md`, `/agent-loop.md`, `/permissions.md` | n/d (leídas 2026-10-23) | Subagente con conversación nueva y solo su último mensaje vuelve; profundidad 3 y 20 simultáneos por defecto; `maxTurns` y `maxBudgetUsd` sin límite por defecto, el presupuesto puede excederse en una respuesta; orden hooks, deny, ask, modo, allow; compactación y `PreCompact`; sesiones resume y fork | D (lectura literal de cinco páginas; no se abrieron las referencias de API) |
| A10 | Claude Code best practices. https://code.claude.com/docs/en/best-practices | n/d | Comprobación ejecutable, contexto limpio, revisión adversarial | O |

## Otros proveedores

| Clave | Fuente | Fecha | Uso | Evidencia |
|---|---|---|---|---|
| OA1 | OpenAI, A practical guide to building agents (PDF). https://cdn.openai.com/business-guides-and-resources/a-practical-guide-to-building-agents.pdf | n/d | Un agente primero; solape de herramientas más que número; riesgo por herramienta; guardarraíles en capas; escalado a persona por umbral de fallos y acciones de alto riesgo | O (leído completo, texto extraído del PDF) |
| OA2 | OpenAI Agents SDK, guardrails. https://openai.github.io/openai-agents-python/guardrails/ | n/d | Ámbitos de guardarraíl; `run_in_parallel`; una excepción no es un veredicto; el texto de bloqueo se persiste | D |
| B1 | Böckeler (Thoughtworks), Harness engineering for coding agent users. https://martinfowler.com/articles/harness-engineering.html | 2026-04-02 | Guías (feedforward) y sensores (feedback); controles computacionales e inferenciales; bucle de ajuste | O: sin cifras ni experimentos propios; la autora declara que el comportamiento funcional no está resuelto (lectura vía resumen de página) |
| G1 | google-research/harness2. https://github.com/google-research/harness2 | n/d | Escalera de remedios; checkpoint con huella; autoedición | M autodeclarada |
| G2 | Google ADK, agentes de flujo. https://adk.dev/ | n/d | El bucle no para solo | D |

## Comunidad e investigación

| Clave | Fuente | Fecha | Uso | Evidencia |
|---|---|---|---|---|
| C1 | Cognition, Don't build multi-agents. https://cognition.com/blog/dont-build-multi-agents | 2025-06-12 | Escritura con decisiones acopladas: hilo único | O |
| C2 | Huntley, Ralph Wiggum loop. https://ghuntley.com/ralph/ | 2025-07-14 | Un ítem por vuelta; presión de retorno | O |
| C3 | 12-factor agents. https://github.com/humanlayer/12-factor-agents | n/d | Poseer el flujo de control; humano como llamada a herramienta | O |
| C5 | ADAS. https://arxiv.org/abs/2408.08435 | 2024-08-15 | Meta-agente que diseña agentes | Experimental (solo abstract) |
| C6 | Composio, best AI agent harnesses. https://composio.dev/content/best-ai-agent-harnesses | 2026-08-04 | Mismo modelo en 8 harnesses: 68 %-88 % en 25 tareas. Un solo modelo, una ejecución por tarea, 4 puntos por tarea; la brecha son 5 tareas. Estudio de un proveedor | M, débil |
| C7 | Marmelab, The State Of AI Harness Engineering 2026. https://marmelab.com/blog/2026/09/24/the-state-of-ai-harness-engineering-2026.html | 2026-09-24 | Encuesta; solo se usa lo verificado abajo | Mezcla |
| M1 | SWE-agent. https://arxiv.org/abs/2405.15793 | 2024-05-06 | La interfaz diseñada para el agente importa | M (abstract) |
| S1 | Agent Skills, estándar. https://agentskills.io/specification | n/d | Formato de skill y evals | D |

## Verificación de las cifras de Marmelab (C7) contra su fuente primaria, 2026-10-23

| Cifra de Marmelab | Estado | Detalle |
|---|---|---|
| 4,4 % de reglas de seguridad con control real en 481 ficheros CLAUDE.md | **Verificada con matiz** | Fuente enlazada: arXiv 2608.23550 (Yan, 2026-08-24). 4,4 % (IC 95 %: 2,6-6,7) es el criterio más estricto; con otros criterios el rango es 4-16 % |
| 60 % de 97 harnesses sin tests ni evaluación | **No verificable** | Medición propia de Marmelab sobre 246 repositorios; sin fuente externa |
| Un segundo revisor baja el éxito un 8 % (base 41 %) | **Discrepante: no usar** | Fuente enlazada: arXiv 2603.25723. La tabla de ablación no tiene ese resultado; el módulo verificador da +0,2 (SWE) y +8,4 (OSWorld). La skill no la cita |
| Más de cuatro traspasos «casi siempre fallan» | **No verificada** | La página de Microsoft enlazada no devolvió cuerpo. Solo como pista |
| Ficheros de contexto generados por máquina bajan el éxito y suben el coste más de un 20 % | **Discrepante en parte** | Fuente: arXiv 2602.11988 (Gloaguen et al.). El +20 % de coste está en el abstract; el efecto sobre el éxito es negativo pero pequeño y no significativo (resumen de modelo en esa sección) |
| Mismo modelo, 8 harnesses, 68 %-88 % | **Verificada con matiz** | Ver C6 |

La lectura de las páginas de arXiv más allá de ~39k caracteres pasó por un resumen de modelo; las dos discrepancias se apoyan en tablas leídas literalmente (primer caso) y en el abstract (segundo).

## Qué no se pudo abrir

- Los artículos completos de SWE-agent, ADAS, ACE, METR, Voyager y harness2: solo abstracts o README.
- Las referencias de API del SDK y la página de subagentes de Claude Code.
- El PDF de arXiv «Stop comparing agents without disclosing the harness»: solo título.
