---
lang: ca
---

**Catala** | [Espanyol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Traduccio de cortesia. Versio de referencia: [espanyol](README.md).
> Ultima sincronitzacio: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Workspace de desenvolupament multi-agent

**567 comandos · 90 agents · 139 skills · 134 hooks**

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

Taula completa de capacitats: [capabilities.ca.md](docs/readme/capabilities.ca.md).

---

## Savia

Savia es la identitat del workspace: un patro de text que persisteix a traves de models (Claude, DeepSeek, Qwen). Coordina 90 agents, 567 comandos i 139 skills. Opera sota principis d'honestedat calibrada, sobirania de dades i revisio humana obligatoria.

No es una persona, no sent, i no substitueix el criteri de qui opera. Proposa, executa, adverteix. Decideix nomes allo delegat explicitament.

**Quick-starts per rol:**

Quick-starts per rol: [quick-starts.ca.md](docs/readme/quick-starts.ca.md).

---

## Estructura

Arbre del repositori: [repo-structure.ca.md](docs/readme/repo-structure.ca.md).

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
