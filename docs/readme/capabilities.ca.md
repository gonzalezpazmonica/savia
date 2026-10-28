# Capacitats

| Area | Que fa |
|---|---|
| Gestio de projectes | Sprints, burndown, capacitat, dailies, retros, KPIs. Informes en Excel i PowerPoint. Prediccio amb Monte Carlo. Facturacio. |
| Spec-Driven Development | Tasques es converteixen en specs executables. 90 agents implementen en 16 llenguatges (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) en worktrees aillats. Code review automatic + revisio humana obligatoria. Compatible amb `github/spec-kit`. |
| Seguretat | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamic, SBOM, compliance sectorial (12 sectors). Savia Shield: classificacio local de dades amb LLM on-premise, emmascarament reversible, signatura criptografica de PRs. |
| Code Review Court | 5 jutges especialitzats (correctness, architecture, security, cognitive, spec) revisen en paral·lel amb scoring 0-100 i gate de 400 LOC. |
| Sobirania d'inferencia | API Anthropic per defecte. Fallback automatic a Ollama local (Gemma 4) en cas d'error de xarxa, HTTP 5xx, HTTP 429 o timeout. Circuit breaker integrat. |
| Memoria persistent | Text pla (JSONL). Entity recall, cerca semantica, continuitat entre sessions. Extraccio automatica de decisions. Personal Vault xifrat AES-256. |
| Accessibilitat | Treball guiat per a persones amb discapacitat (visual, motora, TDAH, autisme, dislexia). Micro-tasques, deteccio de bloquejos, reformulacio adaptativa. |
| Intel·ligencia de codi | Deteccio d'arquitectura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) i `ast-comprehension` amb motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in per projecte). |
| Modes autonoms | Sprint nocturn, millora de codi, investigacio tecnica. Agents proposen en branques `agent/*` amb PRs Draft — l'huma decideix. |
| Extensions | [Savia Mobile](../../projects/savia-mobile-android/README.md) (Android natiu) · Savia Web (Vue.js) · [SaviaClaw](../../zeroclaw/ROADMAP.md) (ESP32 + veu full-duplex) |

---

[README](../../README.ca.md)
