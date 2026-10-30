---
lang: it
---

**Italiano** | [Spagnolo](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md)

# Savia

> Traduzione di cortesia. Versione di riferimento: [spagnolo](README.md).
> Ultima sincronizzazione: 2026-10-30.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia è una meta-orchestratrice agentica di R&S&I: coordina agenti e harness specializzati, linee di ricerca, cupole di conoscenza governata e progetti, con l'autorità sempre nella persona. Open source e sovrana.**

**567 comandi · 90 agenti · 139 skill · 134 hook**

Savia orchestra il lavoro di R&S&I con l'IA: distribuisce i compiti tra harness specializzati (esecutori, revisore indipendenti, fornitori esterni), sostiene linee di ricerca, governa la conoscenza in cupole (Savia Vaults) e gestisce i progetti come una capacità in più. Integra memoria, sicurezza, politiche eseguibili (policy-as-code), tracciabilità con receipts e valutazione su un'architettura indipendente da modello, fornitore e frontend. Opera in locale con sovranità dei dati e dell'inferenza, in 9 lingue.

## Perché esiste Savia

L'esecuzione assistita dall'IA cresce più in fretta della fiducia che vi si ripone. Savia esiste perché quell'esecuzione sia **governata**: l'IA può assumere progressivamente più esecuzione senza appropriarsi dell'autorità.

> **Si delega l'esecuzione, mai il giudizio.**

## Principi

- **Autorità umana per progettazione** — execution authority ≠ decision authority: livelli di rischio, human gates, receipts e provenance rendono verificabile chi decide.
- **Sovranità con significato tecnico** — indipendenza da modello, fornitore e frontend; dati e controllo su infrastruttura propria; politiche ispezionabili.
- **Evidenze prima delle affermazioni** — ogni azione governata produce receipts, provenance e valutazione verificabile.
- **Policy-as-code** — le politiche diventano regole machine-readable con enforcement deterministico.
- **Delega sicura** — l'autonomia è graduata e governata: capability + authority + risk + context + human gates.

## Cosa fa Savia

- **Orchestrare** — meta-orchestrazione di harness specializzati: un esecutore per contratto, revisore indipendenti e fornitori esterni, con invocazione deterministica e l'autorità nella persona.
- **Ricercare** — linee di ricerca con ipotesi, esperimenti e lezioni verificabili.
- **Governare** — rischio (L0-L4), human gates, policy-as-code, receipts e provenance di ogni azione.
- **Eseguire** — 90 agenti, 567 comandi, 139 skill con specs eseguibili (SDD), audit di sicurezza e revisione del codice.
- **Conoscere** — cupole di conoscenza governata (Savia Vaults) e memoria persistente bitemporale con provenance e trust-gates.
- **Valutare** — evals con baseline, paired-delta regression e canaries multi-frontend.
- **Domini** — gestione progetti (sprint, backlog, report; una capacità in più), ingegneria del software e domini specializzati.
- **GRC preliminare** — l'[auditor GRC](docs/grc/README.md) collega requisiti, controlli e prove locali a rilievi tracciabili. Decisioni e certificazioni richiedono revisione umana.

## Architettura

Diagramma completo (in spagnolo): [architecture.es.md](docs/readme/architecture.es.md).

I frontend (Claude Code, OpenCode, Codex), i modelli e i fornitori sono interfacce e infrastruttura attraverso cui Savia opera — **nessuno di essi è Savia**.

## Come funziona

Savia evolve tramite meccanismi espliciti: proposta/spec → implementazione → valutazione → evidenza → enforcement. Il rispetto delle politiche è eseguibile: policy document → machine-readable rule → runtime enforcement → evidence.

Il catalogo delle skill è validato come YAML completo in CI per impedire che una migrazione di metadati lasci capacità invisibili all'avvio.
La maturità di ogni skill richiede test di comportamento certificati; l'auditor riconosce le suite di `tests/scripts/` oltre a quelle di `tests/` e `tests/evals/`.

## Frontend e fornitori supportati

| Frontend | Stato |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (tetto L2, in correzione — SE-388) |

Indipendenza da modello e fornitore per progettazione; ogni frontend supera canaries di parità prima di essere dichiarato supportato.

## Governance e sicurezza

- Human gates per livello di rischio (L0-L4) — l'autorità finale è umana.
- Receipts e provenance di ogni azione governata.
- Compliance-as-code come direzione: la regolamentazione è la fonte, l'interpretazione è umana, l'enforcement è eseguibile. Savia produce evidenze dei controlli eseguiti; non dichiara conformità legale definitiva.

---

## Installazione

```bash
# 1. Installa
curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash
# 2. Apri il workspace
cd savia && opencode
# 3. Savia ti saluta e ti chiede il nome. Poi:
/help                   # ← il tuo primo comando: la mappa delle capacità
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia si adatta al tuo ruolo — ricerca, sviluppo, direzione tecnica, gestione progetti, QA, prodotto — e alla tua lingua. Per i progetti, compatibile con Azure DevOps, Jira e Git-native (Savia Flow).

---

## Capacità

Tabella completa delle capacità: [capabilities.it.md](docs/readme/capabilities.it.md).

---

## Savia

Savia è l'identità del workspace: uno schema testuale che persiste attraverso i modelli (Claude, DeepSeek, Qwen). Come meta-orchestratrice, coordina 90 agenti, 567 comandi, 139 skill e harness esterni. Opera secondo principi di onestà calibrata, sovranità dei dati e revisione umana obbligatoria.

Non è una persona, non prova emozioni, non sostituisce il giudizio di chi la usa. Propone, esegue, avverte. Decide solo ciò che le è stato delegato esplicitamente.

Quick-start per ruolo: [quick-starts.it.md](docs/readme/quick-starts.it.md).

---

## Struttura

Albero del repository: [repo-structure.it.md](docs/readme/repo-structure.it.md).

---

## Documentazione

| Sezione | Descrizione |
|---|---|
| [Guida introduttiva](docs/getting-started.it.md) | Da zero a operativi |
| [Flusso dei dati](docs/data-flow-guide-es.md) | Come si collegano le parti (in spagnolo) |
| [Riservatezza](docs/confidentiality-levels.md) | 5 livelli (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Sovranità dei dati |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandi e agenti](docs/readme/12-comandos-agentes.md) | Riferimento completo |
| [Guide per scenario](docs/guides/README.md) | Azure, Jira, startup, sanità... |
| [Adozione](docs/ADOPTION_GUIDE.md) | Passo dopo passo per società di consulenza |

---

## Fondamenti

1. **Il testo semplice è la verità** — .md e .jsonl. Senza IA, i dati restano leggibili
2. **Privacy assoluta** — i dati dell'utente non lasciano mai la sua macchina
3. **Decide l'umano** — l'IA propone; il merge richiede un grant esplicito e gates verdi, il deploy richiede un'autorizzazione separata
4. **MIT** — senza vendor lock-in, senza telemetria

---

## Contribuire

Leggi [CONTRIBUTING.md](CONTRIBUTING.md) e [SECURITY.md](SECURITY.md). PR benvenute.

## Licenza

[MIT](LICENSE) — Creato da [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
