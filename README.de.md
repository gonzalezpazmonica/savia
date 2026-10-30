
**Deutsch** | [Spanisch](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Uebersetzung aus Hoeflichkeit. Referenzversion: [Spanisch](README.md).
> Letzte Synchronisation: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**567 Befehle · 90 Agenten · 139 skills · 134 hooks**

## Multi-Agenten-Entwicklungs-Workspace

**567 Befehle · 90 Agenten · 139 Skills · 134 Hooks · 16 Sprachen · 283+ Test-Suiten**

Agentisches souveränes System zur Steuerung und Ausführung von KI-Arbeit, unabhängig von Modell, Anbieter und Frontend, mit menschlicher Kontrolle by Design. Integriert Agenten, Gedächtnis, Sicherheit, ausführbare Richtlinien, Nachvollziehbarkeit und spezialisierte Domänen. Läuft lokal mit Daten- und Inferenzsouveränität, in 9 Sprachen.

---

## Installation

```bash
# 1. Installieren

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Workspace oeffnen

cd savia && opencode

# 3. Savia begruesst dich und fragt nach deinem Namen. Dann:

/sprint-status          # ← dein erster Befehl
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Windows-Voraussetzung: **Git for Windows (enthält Git Bash)**. Meldet Claude Code `Git Bash wasn't found`, installiere Git (https://git-scm.com/downloads/win) oder setze `CLAUDE_CODE_GIT_BASH_PATH` auf deine `bash.exe` und öffne eine neue Sitzung.

Savia passt sich an deine Rolle an — PM, Entwickler, QA, Product Owner, CEO — und an deine Sprache. Kompatibel mit Azure DevOps, Jira und Git-native (Savia Flow).

---

## Warum Savia existiert

KI-Ausführung regiert werden soll — progressive Ausführung ohne Aneignung der Autorität.

## Prinzipien

Menschliche Autorität by design · Souveränität · Evidenz · Policy-as-code · sichere Delegation.

## Was Savia tut

Govern (L0-L4, Gates, Receipts) · Ausführen · Erinnern · Evaluieren · Domänen.

## Architektur

Governance + Ausführung + Memory → Evidence/Evals → Frontends + Providers.

## Frontends und Anbieter

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, L2).

## Governance und Sicherheit

Human Gates L0-L4. Compliance-as-code: Evidenz, keine definitive Rechtsaussage.

## Faehigkeiten

Vollständige Fähigkeitstabelle: [capabilities.de.md](docs/readme/capabilities.de.md).

---

## Savia

Savia ist die Identitaet des Workspace: ein Textmuster, das ueber Modelle hinweg persistiert (Claude, DeepSeek, Qwen). Sie koordiniert 90 Agenten, 567 Befehle und 139 Skills. Sie arbeitet nach den Prinzipien kalibrierter Ehrlichkeit, Datensouveraenitaet und obligatorischer menschlicher Pruefung.

Sie ist keine Person, fuehlt nicht und ersetzt nicht das Urteil der ausfuehrenden Person. Sie schlaegt vor, fuehrt aus, warnt. Sie entscheidet nur, was ausdruecklich delegiert wurde.

**Quick-Starts nach Rolle:**

Quick-Starts nach Rolle: [quick-starts.de.md](docs/readme/quick-starts.de.md).

---

## Struktur

Repository-Struktur: [repo-structure.de.md](docs/readme/repo-structure.de.md).

---

## Dokumentation

| Abschnitt | Beschreibung |
|---|---|
| [Erste Schritte](docs/getting-started.md) | Von Null auf produktiv |
| [Datenfluss](docs/data-flow-guide-es.md) | Wie die Teile verbunden sind |
| [Vertraulichkeit](docs/confidentiality-levels.md) | 5 Stufen (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Datensouveraenitaet |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Befehle und Agenten](docs/readme/12-comandos-agentes.md) | Vollstaendige Referenz |
| [Szenario-Anleitungen](docs/guides/README.md) | Azure, Jira, Startup, Gesundheit... |
| [Einfuehrung](docs/ADOPTION_GUIDE.md) | Schritt fuer Schritt fuer Beratungen |

---

## Prinzipien

1. **Klartext ist Wahrheit** — .md und .jsonl. Ohne KI bleiben die Daten lesbar
2. **Absoluter Datenschutz** — Benutzerdaten verlassen nie den Rechner
3. **Der Mensch entscheidet** — KI schlaegt vor, nie autonomer Merge oder Deploy
4. **MIT** — kein Vendor Lock-in, keine Telemetrie

---

## Beitragen

Lies [CONTRIBUTING.md](CONTRIBUTING.md) und [SECURITY.md](SECURITY.md). PRs willkommen.

## Lizenz

[MIT](LICENSE) — Erstellt von [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
