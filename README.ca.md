---
lang: ca
---

**Catala** | [Espanyol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# Savia

> Traducció de cortesia. Versió de referència: [espanyol](README.md).
> Última sincronització: 2026-10-30.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/savia?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia és una metaorquestradora agèntica d'R+D+I: coordina agents i harnesses especialitzats, línies de recerca, cúpules de coneixement governat i projectes, amb l'autoritat sempre en la persona. Open source i sobirana.**

**567 ordres · 90 agents · 139 skills · 134 hooks**

Savia orquestra el treball d'R+D+I amb IA: reparteix tasques entre harnesses especialitzats (executors, revisores independents, proveïdors externs), sosté línies de recerca, governa el coneixement en cúpules (Savia Vaults) i gestiona projectes com una capacitat més. Integra memòria, seguretat, polítiques executables (policy-as-code), traçabilitat amb receipts i avaluació sobre una arquitectura independent de model, proveïdor i frontend. Opera en local amb sobirania de dades i d'inferència, en 9 idiomes.

## Per què existeix Savia

L'execució assistida per IA creix més de pressa que la confiança que s'hi té. Savia existeix perquè aquesta execució sigui **governada**: la IA pot assumir progressivament més execució sense apropiar-se de l'autoritat.

> **Es delega l'execució, mai el criteri.**

## Principis

- **Autoritat humana per disseny** — execution authority ≠ decision authority: nivells de risc, human gates, receipts i provenance fan verificable qui decideix.
- **Sobirania amb significat tècnic** — independència de model, proveïdor i frontend; dades i control en infraestructura pròpia; polítiques inspeccionables.
- **Evidència per sobre de claims** — cada acció governada produeix receipts, provenance i avaluació verificable.
- **Policy-as-code** — les polítiques es converteixen en regles machine-readable amb enforcement determinista.
- **Delegació segura** — l'autonomia és graduada i governada: capability + authority + risk + context + human gates.

## Què fa Savia

- **Orquestrar** — metaorquestració de harnesses especialitzats: un executor per contracte, revisores independents i proveïdors externs, amb invocació determinista i l'autoritat en la persona.
- **Investigar** — línies de recerca amb hipòtesis, experiments i lliçons verificables.
- **Governar** — risc (L0-L4), human gates, policy-as-code, receipts i provenance de cada acció.
- **Executar** — 90 agents, 567 ordres, 139 skills amb specs executables (SDD), auditoria de seguretat i revisió de codi.
- **Conèixer** — cúpules de coneixement governat (Savia Vaults) i memòria persistent bitemporal amb provenance i trust-gates.
- **Avaluar** — evals amb baseline, paired-delta regression i canaries multi-frontend.
- **Dominis** — gestió de projectes (sprints, backlog, informes; una capacitat més), enginyeria de programari i dominis especialitzats.
- **GRC preliminar** — l'[auditor GRC](docs/grc/README.md) enllaça requisits, controls i proves locals amb troballes traçables. Les decisions i certificacions requereixen revisió humana.

## Arquitectura

Diagrama complet (en espanyol): [architecture.es.md](docs/readme/architecture.es.md).

Els frontends (Claude Code, OpenCode, Codex), els models i els proveïdors són interfícies i infraestructura mitjançant les quals opera Savia — **cap d'ells és Savia**.

## Com funciona

Savia evoluciona mitjançant mecanismes explícits: proposta/spec → implementació → avaluació → evidència → enforcement. El compliment de polítiques és executable: policy document → machine-readable rule → runtime enforcement → evidence.

El catàleg de skills es valida com a YAML complet a CI per impedir que una migració de metadades deixi capacitats invisibles en arrencar.
La maduresa de cada skill exigeix proves de comportament certificades; l'auditor reconeix les suites de `tests/scripts/` a més de les de `tests/` i `tests/evals/`.

## Frontends i proveïdors suportats

| Frontend | Estat |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (sostre L2, en remediació — SE-388) |

Independència de model i proveïdor per disseny; cada frontend passa canaries de paritat abans de declarar-se suportat.

## Governança i seguretat

- Human gates per nivell de risc (L0-L4) — l'autoritat final és humana.
- Receipts i provenance de cada acció governada.
- Compliance-as-code com a direcció: la regulació és la font, la interpretació és humana, l'enforcement és executable. Savia produeix evidència de controls executats; no declara compliment legal definitiu.

---

## Instal·lació

```bash
# 1. Instal·la
curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash
# 2. Obre el workspace
cd savia && opencode
# 3. Savia et saluda i et pregunta el nom. Després:
/help                   # ← la teva primera ordre: el mapa de capacitats
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia s'adapta al teu rol — recerca, desenvolupament, direcció tècnica, gestió de projectes, QA, producte — i al teu idioma. Per a projectes, compatible amb Azure DevOps, Jira i Git-native (Savia Flow).

---

## Capacitats

Taula completa de capacitats: [capabilities.ca.md](docs/readme/capabilities.ca.md).

---

## Savia

Savia és la identitat del workspace: un patró de text que persisteix a través de models (Claude, DeepSeek, Qwen). Com a metaorquestradora, coordina 90 agents, 567 ordres, 139 skills i harnesses externs. Opera sota principis d'honestedat calibrada, sobirania de dades i revisió humana obligatòria.

No és una persona, no sent, no substitueix el criteri de qui l'opera. Proposa, executa, adverteix. Decideix només el que se li ha delegat explícitament.

Quick-starts per rol: [quick-starts.ca.md](docs/readme/quick-starts.ca.md).

---

## Estructura

Arbre del repositori: [repo-structure.ca.md](docs/readme/repo-structure.ca.md).

---

## Documentació

| Secció | Descripció |
|---|---|
| [Guia d'inici](docs/getting-started.ca.md) | De zero a productiu |
| [Flux de dades](docs/data-flow-guide-es.md) | Com es connecten les parts (en espanyol) |
| [Confidencialitat](docs/confidentiality-levels.md) | 5 nivells (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Sobirania de dades |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Ordres i agents](docs/readme/12-comandos-agentes.md) | Referència completa |
| [Guies per escenari](docs/guides/README.md) | Azure, Jira, startup, sanitat... |
| [Adopció](docs/ADOPTION_GUIDE.md) | Pas a pas per a consultores |

---

## Fonaments

1. **El text pla és la veritat** — .md i .jsonl. Sense IA, les dades continuen sent llegibles
2. **Privacitat absoluta** — les dades de l'usuari mai surten de la seva màquina
3. **L'humà decideix** — la IA proposa; el merge exigeix un grant exprés i gates en verd, el deploy requereix autorització separada
4. **MIT** — sense vendor lock-in, sense telemetria

---

## Contribuir

Llegeix [CONTRIBUTING.md](CONTRIBUTING.md) i [SECURITY.md](SECURITY.md). PRs benvinguts.

## Llicència

[MIT](LICENSE) — Creat per [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
