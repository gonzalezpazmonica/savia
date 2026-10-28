
**Francais** | [Espagnol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# Savia

> Traduction de courtoisie. Version de reference : [espagnol](README.md).
> Derniere synchronisation : 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Workspace de developpement multi-agent

**567 commandes · 90 agents · 139 skills · 134 hooks**

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

Tableau complet des capacités : [capabilities.fr.md](docs/readme/capabilities.fr.md).

---

## Savia

Savia est l'identite du workspace : un motif textuel qui persiste a travers les modeles (Claude, DeepSeek, Qwen). Elle coordonne 90 agents, 567 commandes et 139 skills. Elle opere selon les principes d'honnetete calibree, de souverainete des donnees et de revue humaine obligatoire.

Elle n'est pas une personne, ne ressent pas, et ne remplace pas le jugement de la personne qui opere. Elle propose, execute, avertit. Elle ne decide que ce qui est explicitement delegue.

**Quick-starts par role :**

Quick-starts par rôle : [quick-starts.fr.md](docs/readme/quick-starts.fr.md).

---

## Structure

Arborescence du dépôt : [repo-structure.fr.md](docs/readme/repo-structure.fr.md).

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
