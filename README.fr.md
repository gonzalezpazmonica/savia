<!-- Header image removed per SE-259 S2 -->

**Francais** | [Espagnol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# Savia

> Traduction de courtoisie. Version de reference : [espagnol](README.md).
> Derniere synchronisation : 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Workspace de developpement multi-agent

**567 commandes · 89 agents · 136 skills · 124 hooks**

Système agentique souverain pour gouverner et exécuter le travail assisté par IA, indépendant du modèle, du fournisseur et du frontend, avec le critère humain by design.

---

## Installation

```bash
# 1. Installez

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Ouvrez le workspace

cd savia && opencode

# 3. Savia vous salue et demande votre nom. Ensuite :

/sprint-status          # ← votre premiere commande
```

**Windows :** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia s'adapte a votre role — PM, developpeur, QA, Product Owner, CEO — et a votre langue. Compatible avec Azure DevOps, Jira et Git-native (Savia Flow).

---

## Pourquoi Savia existe

L'exécution assistée par IA croît plus vite que la confiance qu'elle inspire. Savia existe pour que cette exécution soit gouvernée : l'IA peut prendre progressivement plus d'exécution sans s'approprier l'autorité.

## Principes

Autorité humaine by design · souveraineté à sens technique · preuve plutôt que promesses · policy-as-code · délégation sûre.

## Ce que fait Savia

Gouverner (risque L0-L4, gates, receipts) · exécuter (agents, commands, skills, SDD) · mémoriser (mémoire bitemporale) · évaluer (evals avec baseline) · domaines spécialisés.

## Architecture

Gouvernance (Policy/Risk/Gates) + Exécution (Agents/Skills/Tools) + Mémoire (Context/Knowledge/History) → Evidence/Evals → Frontends + Providers.

## Frontends et fournisseurs

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, plafond L2). Indépendance du modèle et du fournisseur by design.

## Gouvernance et sécurité

Human gates par niveau de risque (L0-L4). Compliance-as-code comme direction : Savia produit des preuves des contrôles exécutés ; ne déclare pas de conformité légale définitive.

## Capacites

| Domaine | Ce que ca fait |
|---|---|
| Gestion de projets | Sprints, burndown, capacite, dailies, retros, KPIs. Rapports Excel et PowerPoint. Prevision Monte Carlo. Facturation. |
| Spec-Driven Development | Les taches deviennent des specs executables. 89 agents implementent en 16 langages (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) dans des worktrees isoles. Code review automatique + revue humaine obligatoire. Compatible avec `github/spec-kit`. |
| Securite | SAST contre OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dynamique, SBOM, conformite sectorielle (12 secteurs). Savia Shield : classification locale des donnees avec LLM on-premise, masquage reversible, signature cryptographique des PRs. |
| Code Review Court | 5 juges specialises (correctness, architecture, security, cognitive, spec) examinent en parallele avec scoring 0-100 et un seuil de 400 LOC. |
| Souverainete d'inference | API Anthropic par defaut. Fallback automatique vers Ollama local (Gemma 4) en cas d'erreur reseau, HTTP 5xx, HTTP 429 ou timeout. Circuit breaker integre. |
| Memoire persistante | Texte brut (JSONL). Entity recall, recherche semantique, continuite entre sessions. Extraction automatique des decisions. Personal Vault chiffre AES-256. |
| Accessibilite | Travail guide pour les personnes en situation de handicap (visuel, moteur, TDAH, autisme, dyslexie). Micro-taches, detection de blocages, reformulation adaptative. |
| Intelligence du code | Detection d'architecture (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) et `ast-comprehension` avec moteur optionnel [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in par projet). |
| Modes autonomes | Sprint nocturne, amelioration du code, recherche technique. Les agents proposent sur des branches `agent/*` avec des PRs Draft — l'humain decide. |
| Extensions | [Savia Mobile](projects/savia-mobile-android/README.md) (Android natif) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + voix full-duplex) |

---

## Savia

Savia est l'identite du workspace : un motif textuel qui persiste a travers les modeles (Claude, DeepSeek, Qwen). Elle coordonne 89 agents, 567 commandes et 136 skills. Elle opere selon les principes d'honnetete calibree, de souverainete des donnees et de revue humaine obligatoire.

Elle n'est pas une personne, ne ressent pas, et ne remplace pas le jugement de la personne qui opere. Elle propose, execute, avertit. Elle ne decide que ce qui est explicitement delegue.

**Quick-starts par role :**

| Role | Quick-start |
|---|---|
| PM / Scrum Master | [→ quick-start-pm](docs/quick-starts/quick-start-pm.md) |
| Tech Lead | [→ quick-start-tech-lead](docs/quick-starts/quick-start-tech-lead.md) |
| Developer | [→ quick-start-developer](docs/quick-starts/quick-start-developer.md) |
| QA | [→ quick-start-qa](docs/quick-starts/quick-start-qa.md) |
| Product Owner | [→ quick-start-po](docs/quick-starts/quick-start-po.md) |
| CEO / CTO | [→ quick-start-ceo](docs/quick-starts/quick-start-ceo.md) |

---

## Structure

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 567 commandes
│   ├── agents/         ← 89 agents specialises (7 avec decision trees : SPEC-147)
│   ├── skills/         ← 136 skills de domaine
│   ├── hooks/          ← 124 hooks deterministes
│   └── rules/          ← regles de contexte et de langage
├── docs/               ← guides par role, scenario, secteur
├── projects/           ← projets (git-ignores pour la confidentialite)
├── scripts/            ← validation, CI, utilitaires
├── zeroclaw/           ← materiel ESP32 + voix
└── CLAUDE.md           ← identite et regles fondamentales
```

---

## Documentation

| Section | Description |
|---|---|
| [Guide de demarrage](docs/getting-started.md) | De zero a productif |
| [Flux de donnees](docs/data-flow-guide-es.md) | Comment les parties se connectent |
| [Confidentialite](docs/confidentiality-levels.md) | 5 niveaux (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Souverainete des donnees |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Commandes et agents](docs/readme/12-comandos-agentes.md) | Reference complete |
| [Guides par scenario](docs/guides/README.md) | Azure, Jira, startup, sante... |
| [Adoption](docs/ADOPTION_GUIDE.md) | Pas a pas pour les cabinets de conseil |

---

## Principes

1. **Le texte brut est la verite** — .md et .jsonl. Sans IA, les donnees restent lisibles
2. **Confidentialite absolue** — les donnees de l'utilisateur ne quittent jamais sa machine
3. **L'humain decide** — l'IA propose, jamais de merge ni de deploy autonome
4. **MIT** — pas de vendor lock-in, pas de telemetrie

---

## Contribuer

Lisez [CONTRIBUTING.md](CONTRIBUTING.md) et [SECURITY.md](SECURITY.md). PRs bienvenus.

## Licence

[MIT](LICENSE) — Cree par [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
