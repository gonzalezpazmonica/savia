# Guida Introduttiva — pm-workspace

> Da zero a produttivo in 15 minuti.

---

## 1. Prerequisiti

- **Claude Code / OpenCode** installato e autenticato (`claude --version` o `opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 per PR e issue (`gh --version`)
- **jq** per il parsing JSON (`jq --version`)
- (Opzionale) **Ollama** per Savia Shield (`ollama --version`)

## 2. Clonare e primo avvio

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

All'avvio, Savia rileva l'assenza di un profilo e si presenta. Rispondi alle sue domande: nome, ruolo, progetti. Questo crea il tuo profilo in `.claude/profiles/users/{slug}/`.

Se vuoi saltare il profilo: scrivi direttamente un comando. Savia non insiste.

## 3. Configurare il tuo progetto

```bash
/project-new
```

Segui il wizard. Savia rileva il tuo strumento PM (Azure DevOps, Jira o Savia Flow) e crea la struttura in `projects/{nome}/`.

Per Azure DevOps, ti serve un PAT salvato in `$HOME/.azure/devops-pat` (una riga, senza a capo). Scopes: Work Items R/W, Project R, Analytics R.

## 4. Profili hook (Savia Shield)

Gli hook controllano quali regole vengono eseguite automaticamente. Ci sono 4 profili:

| Profilo | Cosa attiva | Quando usarlo |
|---------|------------|---------------|
| `minimal` | Solo sicurezza base | Demo, primi passi |
| `standard` | Sicurezza + qualita | Lavoro quotidiano (predefinito) |
| `strict` | Sicurezza + qualita + scrutinio extra | Pre-release, codice critico |
| `ci` | Come standard, non interattivo | Pipeline CI/CD |

```bash
# Vedere il profilo attivo
bash scripts/hook-profile.sh get

# Cambiare profilo
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (protezione dati)

Se lavori con dati dei clienti, attiva Savia Shield:

```bash
/savia-shield enable
/savia-shield status
```

Shield protegge i dati sensibili (N4/N4b) dalla fuoriuscita verso file pubblici (N1). Funziona con 5 livelli: regex, LLM locale, audit post-scrittura, mascheramento reversibile e rilevamento base64.

Guida completa: [docs/savia-shield-guide.it.md](savia-shield-guide.it.md)

## 6. Mappe: .scm e .ctx

pm-workspace genera due indici navigabili:

- **`.scm` (Capability Map)**: catalogo di comandi, skill e agenti indicizzati per intenzione. Risponde a "cosa puo fare Savia".
- **`.ctx` (Context Index)**: mappa di dove risiede ogni tipo di informazione (regole, memoria, progetti). Risponde a "dove cercare o salvare dati".

Entrambi sono testo semplice, auto-generati, con caricamento progressivo (L0/L1/L2).

Stato: in proposta (SPEC-053, SPEC-054). Quando disponibili, si generano con:

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Quickstart per ruolo

| Ruolo | Primi comandi | Routine quotidiana |
|-------|---------------|-------------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PR, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Ogni ruolo ha una guida dettagliata: `docs/quick-starts/quick-start-{ruolo}.md`

## 8. Riferimento configurazione

| Cosa configurare | Dove | Esempio |
|------------------|------|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Token su una riga |
| Profilo utente | `.claude/profiles/users/{slug}/` | Creato da `/profile-setup` |
| Profilo hook | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Connettori | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Progetto strumento PM | `projects/{nome}/CLAUDE.md` | Org URL, iteration path |
| Config privata | `CLAUDE.local.md` (gitignored) | Progetti reali |

## 9. Prestazioni

- **CLAUDE.md consuma token ad ogni turno** (non viene messo in cache) — mantienilo snello e sotto le 150 righe
- **Gli skill non consumano contesto finche non vengono invocati** — avere molti skill e gratuito
- **auto-compact si attiva al 65%** della finestra di contesto — esegui `/compact` manualmente se noti un degrado prima
- **Le voci di memoria devono essere < 150 caratteri** — riassunti brevi si caricano piu velocemente e occupano meno contesto
- Dettagli completi: `docs/best-practices-claude-code.md`

## 10. Prossimi passi

1. Esegui `/help` per vedere il catalogo interattivo dei comandi
2. Esegui `/daily-routine` per farti proporre la tua routine da Savia
3. Leggi la guida del tuo ruolo in `docs/quick-starts/`
4. Se lavori con dati dei clienti: attiva Savia Shield
5. Se qualcosa non funziona: `/workspace-doctor` diagnostica l'ambiente

---

> Documentazione dettagliata: `docs/readme/` (13 sezioni) e `docs/guides/` (15 guide per scenario).
