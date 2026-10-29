# Capacites

| Domaine | Ce que ca fait |
|---|---|
| Gestion de projets | Sprints, burndown, capacite, dailies, retros, KPIs. Rapports Excel et PowerPoint. Prevision Monte Carlo. Facturation. |
| Spec-Driven Development | Les taches deviennent des specs executables. 90 agents implementent en 16 langages (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) dans des worktrees isoles. Code review automatique + revue humaine obligatoire. Compatible avec `github/spec-kit`. |
| Securite | SAST contre OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dynamique, SBOM, conformite sectorielle (12 secteurs). Savia Shield : classification locale des donnees avec LLM on-premise, masquage reversible, signature cryptographique des PRs. |
| Code Review Court | 5 juges specialises (correctness, architecture, security, cognitive, spec) examinent en parallele avec scoring 0-100 et un seuil de 400 LOC. |
| Souverainete d'inference | API Anthropic par defaut. Fallback automatique vers Ollama local (Gemma 4) en cas d'erreur reseau, HTTP 5xx, HTTP 429 ou timeout. Circuit breaker integre. |
| Memoire persistante | Texte brut (JSONL). Entity recall, recherche semantique, continuite entre sessions. Extraction automatique des decisions. Personal Vault chiffre AES-256. |
| Accessibilite | Travail guide pour les personnes en situation de handicap (visuel, moteur, TDAH, autisme, dyslexie). Micro-taches, detection de blocages, reformulation adaptative. |
| Intelligence du code | Detection d'architecture (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) et `ast-comprehension` avec moteur optionnel [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in par projet). |
| Modes autonomes | Sprint nocturne, amelioration du code, recherche technique. Les agents proposent sur des branches `agent/*` avec des PRs Draft — l'humain decide. |
| Extensions | [Savia Mobile](../../projects/savia-mobile-android/README.md) (Android natif) · Savia Web (Vue.js) · [SaviaClaw](../../zeroclaw/ROADMAP.md) (ESP32 + voix full-duplex) |

---

[README](../../README.fr.md)
