# Capacita

| Area | Cosa fa |
|---|---|
| Gestione progetti | Sprint, burndown, capacita, daily, retro, KPI. Report in Excel e PowerPoint. Previsione Monte Carlo. Fatturazione. |
| Spec-Driven Development | I task diventano spec eseguibili. 90 agenti implementano in 16 linguaggi (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) in worktree isolati. Code review automatica + revisione umana obbligatoria. Compatibile con `github/spec-kit`. |
| Sicurezza | SAST contro OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamico, SBOM, compliance settoriale (12 settori). Savia Shield: classificazione locale dei dati con LLM on-premise, mascheramento reversibile, firma crittografica dei PR. |
| Code Review Court | 5 giudici specializzati (correctness, architecture, security, cognitive, spec) esaminano in parallelo con scoring 0-100 e gate di 400 LOC. |
| Sovranita di inferenza | API Anthropic per default. Fallback automatico a Ollama locale (Gemma 4) in caso di errore di rete, HTTP 5xx, HTTP 429 o timeout. Circuit breaker integrato. |
| Memoria persistente | Testo semplice (JSONL). Entity recall, ricerca semantica, continuita tra sessioni. Estrazione automatica delle decisioni. Personal Vault cifrato AES-256. |
| Accessibilita | Lavoro guidato per persone con disabilita (visiva, motoria, ADHD, autismo, dislessia). Micro-task, rilevamento blocchi, riformulazione adattiva. |
| Intelligenza del codice | Rilevamento architettura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness function. Human Code Maps (.hcm). Agent Code Maps (.acm) e `ast-comprehension` con motore opzionale [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in per progetto). |
| Modalita autonome | Sprint notturno, miglioramento codice, ricerca tecnica. Agenti propongono su branch `agent/*` con PR Draft — l'umano decide. |
| Estensioni | [Savia Mobile](../../projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](../../zeroclaw/ROADMAP.md) (ESP32 + voce full-duplex) |

---

[README](../../README.it.md)
