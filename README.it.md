---
lang: it
---

<!-- Header image removed per SE-259 S2 -->

**Italiano** | [Spagnolo](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md)

# Savia

> Traduzione di cortesia. Versione di riferimento: [spagnolo](README.md).
> Ultima sincronizzazione: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**567 comandi · 89 agenti · 136 skills · 124 hook**

## Workspace di sviluppo multi-agente

**567 comandi · 89 agenti · 136 skill · 124 hook · 16 linguaggi · 283+ suite di test**

Sistema agentico sovrano per governare ed eseguire lavoro con IA, indipendente da modello, fornitore e frontend, con criterio umano by design. Integra agenti, memoria, sicurezza, policy eseguibili, tracciabilità e domini specializzati. Opera in locale con sovranità dei dati e dell'inferenza, in 9 lingue.

---

## Installazione

```bash
# 1. Installa

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Apri il workspace

cd savia && opencode

# 3. Savia ti saluta e ti chiede il nome. Poi:

/sprint-status          # ← il tuo primo comando
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia si adatta al tuo ruolo — PM, developer, QA, Product Owner, CEO — e alla tua lingua. Compatibile con Azure DevOps, Jira e Git-native (Savia Flow).

---

## Perché esiste Savia

L'esecuzione IA deve essere governata — esecuzione progressiva senza appropriazione di autorità.

## Principi

Autorità umana by design · sovranità tecnica · evidenza · policy-as-code · delegazione sicura.

## Cosa fa Savia

Governare (L0-L4, gates, receipt) · eseguire · ricordare · valutare · domini.

## Architettura

Governance + Esecuzione + Memoria → Evidence/Evals → Frontend + Provider.

## Frontend e fornitori

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, tetto L2).

## Governance e sicurezza

Human gate L0-L4. Compliance-as-code: evidenza, non dichiarazione legale definitiva.

## Capacita

| Area | Cosa fa |
|---|---|
| Gestione progetti | Sprint, burndown, capacita, daily, retro, KPI. Report in Excel e PowerPoint. Previsione Monte Carlo. Fatturazione. |
| Spec-Driven Development | I task diventano spec eseguibili. 89 agenti implementano in 16 linguaggi (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) in worktree isolati. Code review automatica + revisione umana obbligatoria. Compatibile con `github/spec-kit`. |
| Sicurezza | SAST contro OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamico, SBOM, compliance settoriale (12 settori). Savia Shield: classificazione locale dei dati con LLM on-premise, mascheramento reversibile, firma crittografica dei PR. |
| Code Review Court | 5 giudici specializzati (correctness, architecture, security, cognitive, spec) esaminano in parallelo con scoring 0-100 e gate di 400 LOC. |
| Sovranita di inferenza | API Anthropic per default. Fallback automatico a Ollama locale (Gemma 4) in caso di errore di rete, HTTP 5xx, HTTP 429 o timeout. Circuit breaker integrato. |
| Memoria persistente | Testo semplice (JSONL). Entity recall, ricerca semantica, continuita tra sessioni. Estrazione automatica delle decisioni. Personal Vault cifrato AES-256. |
| Accessibilita | Lavoro guidato per persone con disabilita (visiva, motoria, ADHD, autismo, dislessia). Micro-task, rilevamento blocchi, riformulazione adattiva. |
| Intelligenza del codice | Rilevamento architettura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness function. Human Code Maps (.hcm). Agent Code Maps (.acm) e `ast-comprehension` con motore opzionale [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in per progetto). |
| Modalita autonome | Sprint notturno, miglioramento codice, ricerca tecnica. Agenti propongono su branch `agent/*` con PR Draft — l'umano decide. |
| Estensioni | [Savia Mobile](projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + voce full-duplex) |

---

## Savia

Savia e l'identita del workspace: un pattern testuale che persiste attraverso modelli (Claude, DeepSeek, Qwen). Coordina 89 agenti, 567 comandi e 136 skill. Opera sotto principi di onesta calibrata, sovranita dei dati e revisione umana obbligatoria.

Non e una persona, non prova emozioni e non sostituisce il giudizio di chi opera. Propone, esegue, avverte. Decide solo quanto delegato esplicitamente.

**Quick-start per ruolo:**

| Ruolo | Quick-start |
|---|---|
| PM / Scrum Master | [→ quick-start-pm](docs/quick-starts/quick-start-pm.md) |
| Tech Lead | [→ quick-start-tech-lead](docs/quick-starts/quick-start-tech-lead.md) |
| Developer | [→ quick-start-developer](docs/quick-starts/quick-start-developer.md) |
| QA | [→ quick-start-qa](docs/quick-starts/quick-start-qa.md) |
| Product Owner | [→ quick-start-po](docs/quick-starts/quick-start-po.md) |
| CEO / CTO | [→ quick-start-ceo](docs/quick-starts/quick-start-ceo.md) |

---

## Struttura

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 567 comandi
│   ├── agents/         ← 89 agenti specializzati (7 con decision trees: SPEC-147)
│   ├── skills/         ← 136 skill di dominio
│   ├── hooks/          ← 124 hook deterministici
│   └── rules/          ← regole di contesto e linguaggio
├── docs/               ← guide per ruolo, scenario, settore
├── projects/           ← progetti (git-ignorati per privacy)
├── scripts/            ← validazione, CI, utilita
├── zeroclaw/           ← hardware ESP32 + voce
└── CLAUDE.md           ← identita e regole fondamentali
```

---

## Documentazione

| Sezione | Descrizione |
|---|---|
| [Guida introduttiva](docs/getting-started.md) | Da zero a produttivo |
| [Flusso dati](docs/data-flow-guide-es.md) | Come si collegano le parti |
| [Riservatezza](docs/confidentiality-levels.md) | 5 livelli (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Sovranita dei dati |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandi e agenti](docs/readme/12-comandos-agentes.md) | Riferimento completo |
| [Guide per scenario](docs/guides/README.md) | Azure, Jira, startup, sanita... |
| [Adozione](docs/ADOPTION_GUIDE.md) | Passo a passo per societa di consulenza |

---

## Principi

1. **Il testo semplice e la verita** — .md e .jsonl. Senza IA, i dati restano leggibili
2. **Privacy assoluta** — i dati dell'utente non lasciano mai la sua macchina
3. **L'umano decide** — l'IA propone, mai merge ne deploy autonomo
4. **MIT** — nessun vendor lock-in, nessuna telemetria

---

## Contribuire

Leggi [CONTRIBUTING.md](CONTRIBUTING.md) e [SECURITY.md](SECURITY.md). PR benvenute.

## Licenza

[MIT](LICENSE) — Creato da [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
