# Capacidades

| Area | O que faz |
|---|---|
| Gestao de projetos | Sprints, burndown, capacidade, dailies, retros, KPIs. Relatorios em Excel e PowerPoint. Previsao com Monte Carlo. Faturacao. |
| Spec-Driven Development | Tarefas convertem-se em specs executaveis. 90 agentes implementam em 16 linguagens (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) em worktrees isolados. Code review automatico + revisao humana obrigatoria. Compativel com `github/spec-kit`. |
| Seguranca | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamico, SBOM, compliance setorial (12 setores). Savia Shield: classificacao local de dados com LLM on-premise, mascaramento reversivel, assinatura criptografica de PRs. |
| Code Review Court | 5 juizes especializados (correctness, architecture, security, cognitive, spec) revisam em paralelo com scoring 0-100 e gate de 400 LOC. |
| Soberania de inferencia | API Anthropic por default. Fallback automatico para Ollama local (Gemma 4) em caso de erro de rede, HTTP 5xx, HTTP 429 ou timeout. Circuit breaker integrado. |
| Memoria persistente | Texto simples (JSONL). Entity recall, pesquisa semantica, continuidade entre sessoes. Extracao automatica de decisoes. Personal Vault cifrado AES-256. |
| Acessibilidade | Trabalho guiado para pessoas com deficiencia (visual, motora, TDAH, autismo, dislexia). Micro-tarefas, detecao de bloqueios, reformulacao adaptativa. |
| Inteligencia de codigo | Detecao de arquitetura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) e `ast-comprehension` com motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in por projeto). |
| Modos autonomos | Sprint noturno, melhoria de codigo, investigacao tecnica. Agentes propoem em branches `agent/*` com PRs Draft — o humano decide. |
| Extensoes | [Savia Mobile](../../projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](../../zeroclaw/ROADMAP.md) (ESP32 + voz full-duplex) |

---

[README](../../README.pt.md)
