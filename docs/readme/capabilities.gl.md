# Capacidades

| Area | Que fai |
|---|---|
| Xestion de proxectos | Sprints, burndown, capacidade, dailies, retros, KPIs. Informes en Excel e PowerPoint. Prediccion con Monte Carlo. Facturacion. |
| Spec-Driven Development | Tarefas convirtense en specs executabeis. 90 axentes implementan en 16 linguaxes (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) en worktrees illados. Code review automatico + revision humana obrigatoria. Compatible con `github/spec-kit`. |
| Seguridade | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamico, SBOM, compliance sectorial (12 sectores). Savia Shield: clasificacion local de datos con LLM on-premise, enmascaramento reversibel, sinatura criptografica de PRs. |
| Code Review Court | 5 xuices especializados (correctness, architecture, security, cognitive, spec) revisan en paralelo con scoring 0-100 e gate de 400 LOC. |
| Soberania de inferencia | API Anthropic por defecto. Fallback automatico a Ollama local (Gemma 4) en caso de erro de rede, HTTP 5xx, HTTP 429 ou timeout. Circuit breaker integrado. |
| Memoria persistente | Texto plano (JSONL). Entity recall, busca semantica, continuidade entre sesions. Extraccion automatica de decisions. Personal Vault cifrado AES-256. |
| Accesibilidade | Traballo guiado para persoas con discapacidade (visual, motora, TDAH, autismo, dislexia). Micro-tarefas, deteccion de bloqueos, reformulacion adaptativa. |
| Intelixencia de codigo | Deteccion de arquitectura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) e `ast-comprehension` con motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in por proxecto). |
| Modos autonomos | Sprint nocturno, mellora de codigo, investigacion tecnica. Axentes proponen en ramas `agent/*` con PRs Draft — o humano decide. |
| Extensions | [Savia Mobile](../../projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](../../zeroclaw/ROADMAP.md) (ESP32 + voz full-duplex) |

---

[README](../../README.gl.md)
