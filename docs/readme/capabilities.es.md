# Capacidades

| Área | Qué hace |
|---|---|
| Gestión de proyectos | Sprints, burndown, capacity, dailies, retros, KPIs. Informes en Excel y PowerPoint. Predicción con Monte Carlo. Facturación. |
| Spec-Driven Development | Tasks se convierten en specs ejecutables. 65 agentes implementan en 16 lenguajes (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) en worktrees aislados. Code review automático + revisión humana, incluida la de la operadora única. Compatible con `github/spec-kit`. |
| Seguridad | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinámico, SBOM, compliance sectorial (12 sectores). Savia Shield: clasificación local de datos con LLM on-premise, masking reversible, firma criptográfica de PRs. |
| Code Review Court | 5 jueces especializados (correctness, architecture, security, cognitive, spec) revisan en paralelo con scoring 0-100 y gate de 400 LOC. |
| Soberanía de inferencia | API Anthropic por defecto. Fallback automático a Ollama local (Gemma 4) ante error de red, HTTP 5xx, HTTP 429 o timeout. Circuit breaker integrado. |
| Memoria persistente | Texto plano (JSONL). Entity recall, búsqueda semántica, continuidad entre sesiones. Extracción automática de decisiones. Personal Vault cifrado AES-256. |
| Accesibilidad | Trabajo guiado para personas con discapacidad (visual, motora, TDAH, autismo, dislexia). Micro-tareas, detección de bloqueos, reformulación adaptativa. |
| Inteligencia de código | Detección de arquitectura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) y `ast-comprehension` con motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in por proyecto). |
| Modos autónomos | Sprint nocturno, mejora de código, investigación técnica. Agentes proponen en ramas `agent/*` con PRs Draft; la operadora única puede revisar y mergear con grant expreso y gates verdes. |
| Extensiones | [Savia Mobile](../../projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](../../zeroclaw/ROADMAP.md) (ESP32 + voz full-duplex) |

---

Volver al [README](../../README.md).
