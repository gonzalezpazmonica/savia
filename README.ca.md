---
lang: ca
---

<!-- Header image removed per SE-259 S2 -->

**Catala** | [Espanyol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Traduccio de cortesia. Versio de referencia: [espanyol](README.md).
> Ultima sincronitzacio: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Workspace de desenvolupament multi-agent

**567 comandos · 89 agents · 136 skills · 124 hooks**

Sistema agèntic sobirà per governar i executar treball amb IA, independent de model, proveïdor i frontend, amb criteri humà per disseny. Integra agents, memòria, seguretat, polítiques executables, traçabilitat i dominis especialitzats. Funciona en local amb sobirania de dades i inferència, en 9 idiomes.

---

## Instal·lacio

```bash
# 1. Instal·la

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Obre el workspace

cd savia && opencode

# 3. Savia et saluda i et pregunta el nom. Despres:

/sprint-status          # ← la teva primera comanda
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia s'adapta al teu rol — PM, developer, QA, Product Owner, CEO — i al teu idioma. Compatible amb Azure DevOps, Jira i Git-native (Savia Flow).

---

## Per què existeix Savia

L'execució assistida per IA creix més ràpid que la confiança sobre ella. Savia existeix perquè aquesta execució sigui governada.

## Principis

Autoritat humana per disseny · sobirania tècnica · evidència sobre claims · policy-as-code · delegació segura.

## Què fa Savia

Gobernar (risc L0-L4, gates, receipts) · executar · recordar · avaluar · dominis.

## Arquitectura

Govern + Execució + Memòria → Evidence/Evals → Frontends + Providers.

## Frontends i proveïdors

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, sostre L2).

## Governança i seguretat

Human gates L0-L4. Compliance-as-code: evidència, no declaració legal definitiva.

## Capacitats

| Area | Que fa |
|---|---|
| Gestio de projectes | Sprints, burndown, capacitat, dailies, retros, KPIs. Informes en Excel i PowerPoint. Prediccio amb Monte Carlo. Facturacio. |
| Spec-Driven Development | Tasques es converteixen en specs executables. 89 agents implementen en 16 llenguatges (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) en worktrees aillats. Code review automatic + revisio humana obligatoria. Compatible amb `github/spec-kit`. |
| Seguretat | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamic, SBOM, compliance sectorial (12 sectors). Savia Shield: classificacio local de dades amb LLM on-premise, emmascarament reversible, signatura criptografica de PRs. |
| Code Review Court | 5 jutges especialitzats (correctness, architecture, security, cognitive, spec) revisen en paral·lel amb scoring 0-100 i gate de 400 LOC. |
| Sobirania d'inferencia | API Anthropic per defecte. Fallback automatic a Ollama local (Gemma 4) en cas d'error de xarxa, HTTP 5xx, HTTP 429 o timeout. Circuit breaker integrat. |
| Memoria persistent | Text pla (JSONL). Entity recall, cerca semantica, continuitat entre sessions. Extraccio automatica de decisions. Personal Vault xifrat AES-256. |
| Accessibilitat | Treball guiat per a persones amb discapacitat (visual, motora, TDAH, autisme, dislexia). Micro-tasques, deteccio de bloquejos, reformulacio adaptativa. |
| Intel·ligencia de codi | Deteccio d'arquitectura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) i `ast-comprehension` amb motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in per projecte). |
| Modes autonoms | Sprint nocturn, millora de codi, investigacio tecnica. Agents proposen en branques `agent/*` amb PRs Draft — l'huma decideix. |
| Extensions | [Savia Mobile](projects/savia-mobile-android/README.md) (Android natiu) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + veu full-duplex) |

---

## Savia

Savia es la identitat del workspace: un patro de text que persisteix a traves de models (Claude, DeepSeek, Qwen). Coordina 89 agents, 567 comandos i 136 skills. Opera sota principis d'honestedat calibrada, sobirania de dades i revisio humana obligatoria.

No es una persona, no sent, i no substitueix el criteri de qui opera. Proposa, executa, adverteix. Decideix nomes allo delegat explicitament.

**Quick-starts per rol:**

| Rol | Quick-start |
|---|---|
| PM / Scrum Master | [→ quick-start-pm](docs/quick-starts/quick-start-pm.md) |
| Tech Lead | [→ quick-start-tech-lead](docs/quick-starts/quick-start-tech-lead.md) |
| Developer | [→ quick-start-developer](docs/quick-starts/quick-start-developer.md) |
| QA | [→ quick-start-qa](docs/quick-starts/quick-start-qa.md) |
| Product Owner | [→ quick-start-po](docs/quick-starts/quick-start-po.md) |
| CEO / CTO | [→ quick-start-ceo](docs/quick-starts/quick-start-ceo.md) |

---

## Estructura

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 567 comandos
│   ├── agents/         ← 89 agents especialitzats (7 amb decision trees: SPEC-147)
│   ├── skills/         ← 136 skills de domini
│   ├── hooks/          ← 124 hooks deterministes
│   └── rules/          ← regles de context i llenguatge
├── docs/               ← guies per rol, escenari, sector
├── projects/           ← projectes (git-ignorats per privacitat)
├── scripts/            ← validacio, CI, utilitats
├── zeroclaw/           ← hardware ESP32 + veu
└── CLAUDE.md           ← identitat i regles fonamentals
```

---

## Documentacio

| Seccio | Descripcio |
|---|---|
| [Guia d'inici](docs/getting-started.md) | De zero a productiu |
| [Flux de dades](docs/data-flow-guide-es.md) | Com es connecten les parts |
| [Confidencialitat](docs/confidentiality-levels.md) | 5 nivells (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Sobirania de dades |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandes i agents](docs/readme/12-comandos-agentes.md) | Referencia completa |
| [Guies per escenari](docs/guides/README.md) | Azure, Jira, startup, sanitat... |
| [Adopcio](docs/ADOPTION_GUIDE.md) | Pas a pas per a consultores |

---

## Principis

1. **El text pla es la veritat** — .md i .jsonl. Sense IA, les dades segueixen llegibles
2. **Privacitat absoluta** — les dades de l'usuari mai surten de la seva maquina
3. **L'huma decideix** — la IA proposa, mai merge ni deploy autonom
4. **MIT** — sense vendor lock-in, sense telemetria

---

## Contribuir

Llegeix [CONTRIBUTING.md](CONTRIBUTING.md) i [SECURITY.md](SECURITY.md). PRs benvinguts.

## Llicencia

[MIT](LICENSE) — Creat per [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
