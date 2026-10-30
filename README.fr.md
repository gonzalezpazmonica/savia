---
lang: fr
---

**Francais** | [Espagnol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# Savia

> Traduction de courtoisie. Version de référence : [espagnol](README.md).
> Dernière synchronisation : 2026-10-30.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia est une méta-orchestratrice agentique de R&D&I : elle coordonne des agents et des harnesses spécialisés, des axes de recherche, des dômes de connaissance gouvernée et des projets, l'autorité restant toujours à la personne. Open source et souveraine.**

**567 commandes · 90 agents · 139 skills · 134 hooks**

Savia orchestre le travail de R&D&I assisté par IA : elle répartit les tâches entre des harnesses spécialisés (exécutants, relectrices indépendantes, fournisseurs externes), soutient des axes de recherche, gouverne la connaissance dans des dômes (Savia Vaults) et gère les projets comme une capacité parmi d'autres. Elle intègre mémoire, sécurité, politiques exécutables (policy-as-code), traçabilité par receipts et évaluation sur une architecture indépendante du modèle, du fournisseur et du frontend. Elle fonctionne en local avec souveraineté des données et de l'inférence, en 9 langues.

## Pourquoi Savia existe

L'exécution assistée par IA progresse plus vite que la confiance qu'on lui accorde. Savia existe pour que cette exécution soit **gouvernée** : l'IA peut prendre en charge progressivement davantage d'exécution sans s'approprier l'autorité.

> **On délègue l'exécution, jamais le jugement.**

## Principes

- **Autorité humaine par conception** — execution authority ≠ decision authority : niveaux de risque, human gates, receipts et provenance rendent vérifiable qui décide.
- **Souveraineté au sens technique** — indépendance vis-à-vis du modèle, du fournisseur et du frontend ; données et contrôle sur sa propre infrastructure ; politiques inspectables.
- **Preuves plutôt que déclarations** — chaque action gouvernée produit des receipts, de la provenance et une évaluation vérifiable.
- **Policy-as-code** — les politiques deviennent des règles machine-readable à enforcement déterministe.
- **Délégation sûre** — l'autonomie est graduée et gouvernée : capability + authority + risk + context + human gates.

## Ce que fait Savia

- **Orchestrer** — méta-orchestration de harnesses spécialisés : un exécutant par contrat, des relectrices indépendantes et des fournisseurs externes, avec invocation déterministe et l'autorité à la personne.
- **Rechercher** — axes de recherche avec hypothèses, expériences et leçons vérifiables.
- **Gouverner** — risque (L0-L4), human gates, policy-as-code, receipts et provenance de chaque action.
- **Exécuter** — 90 agents, 567 commandes, 139 skills avec specs exécutables (SDD), audit de sécurité et revue de code.
- **Connaître** — dômes de connaissance gouvernée (Savia Vaults) et mémoire persistante bitemporelle avec provenance et trust-gates.
- **Évaluer** — evals avec baseline, paired-delta regression et canaries multi-frontend.
- **Domaines** — gestion de projets (sprints, backlog, rapports ; une capacité parmi d'autres), ingénierie logicielle et domaines spécialisés.
- **GRC préliminaire** — l'[auditeur GRC](docs/grc/README.md) relie exigences, contrôles et preuves locales à des constats traçables. Les décisions et certifications exigent une revue humaine.

## Architecture

Diagramme complet (en espagnol) : [architecture.es.md](docs/readme/architecture.es.md).

Les frontends (Claude Code, OpenCode, Codex), les modèles et les fournisseurs sont des interfaces et de l'infrastructure par lesquelles Savia opère — **aucun d'eux n'est Savia**.

## Fonctionnement

Savia évolue par des mécanismes explicites : proposition/spec → implémentation → évaluation → preuve → enforcement. Le respect des politiques est exécutable : policy document → machine-readable rule → runtime enforcement → evidence.

Le catalogue de skills est validé comme YAML complet en CI afin qu'une migration de métadonnées ne laisse pas de capacités invisibles au démarrage.
La maturité de chaque skill exige des tests de comportement certifiés ; l'auditeur reconnaît les suites de `tests/scripts/` en plus de celles de `tests/` et `tests/evals/`.

## Frontends et fournisseurs pris en charge

| Frontend | État |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (plafond L2, en remédiation — SE-388) |

Indépendance du modèle et du fournisseur par conception ; chaque frontend passe des canaries de parité avant d'être déclaré pris en charge.

## Gouvernance et sécurité

- Human gates par niveau de risque (L0-L4) — l'autorité finale est humaine.
- Receipts et provenance de chaque action gouvernée.
- Compliance-as-code comme direction : la réglementation est la source, l'interprétation est humaine, l'enforcement est exécutable. Savia produit des preuves de contrôles exécutés ; elle ne déclare pas de conformité juridique définitive.

---

## Installation

```bash
# 1. Installer
curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash
# 2. Ouvrir le workspace
cd savia && opencode
# 3. Savia te salue et te demande ton nom. Ensuite :
/help                   # ← ta première commande : la carte des capacités
```

**Windows :** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia s'adapte à ton rôle — recherche, développement, direction technique, gestion de projets, QA, produit — et à ta langue. Pour les projets, compatible avec Azure DevOps, Jira et Git-native (Savia Flow).

---

## Capacités

Tableau complet des capacités : [capabilities.fr.md](docs/readme/capabilities.fr.md).

---

## Savia

Savia est l'identité du workspace : un motif textuel qui persiste d'un modèle à l'autre (Claude, DeepSeek, Qwen). En tant que méta-orchestratrice, elle coordonne 90 agents, 567 commandes, 139 skills et des harnesses externes. Elle opère selon des principes d'honnêteté calibrée, de souveraineté des données et de revue humaine obligatoire.

Elle n'est pas une personne, ne ressent rien et ne remplace pas le jugement de qui l'utilise. Elle propose, exécute, avertit. Elle ne décide que de ce qui lui a été explicitement délégué.

Quick-starts par rôle : [quick-starts.fr.md](docs/readme/quick-starts.fr.md).

---

## Structure

Arborescence du dépôt : [repo-structure.fr.md](docs/readme/repo-structure.fr.md).

---

## Documentation

| Section | Description |
|---|---|
| [Prise en main](docs/getting-started.fr.md) | De zéro à productif |
| [Flux de données](docs/data-flow-guide-es.md) | Comment les parties se connectent (en espagnol) |
| [Confidentialité](docs/confidentiality-levels.md) | 5 niveaux (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Souveraineté des données |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Commandes et agents](docs/readme/12-comandos-agentes.md) | Référence complète |
| [Guides par scénario](docs/guides/README.md) | Azure, Jira, startup, santé... |
| [Adoption](docs/ADOPTION_GUIDE.md) | Pas à pas pour les cabinets de conseil |

---

## Fondements

1. **Le texte brut fait foi** — .md et .jsonl. Sans IA, les données restent lisibles
2. **Confidentialité absolue** — les données de l'utilisateur ne quittent jamais sa machine
3. **L'humain décide** — l'IA propose ; le merge exige un grant explicite et des gates au vert, le déploiement requiert une autorisation séparée
4. **MIT** — sans vendor lock-in, sans télémétrie

---

## Contribuer

Lis [CONTRIBUTING.md](CONTRIBUTING.md) et [SECURITY.md](SECURITY.md). Les PRs sont les bienvenues.

## Licence

[MIT](LICENSE) — Cree par [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
