<!-- Header image removed per SE-259 S2 -->

**Deutsch** | [Spanisch](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Uebersetzung aus Hoeflichkeit. Referenzversion: [Spanisch](README.md).
> Letzte Synchronisation: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/pm-workspace/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Multi-Agenten-Entwicklungs-Workspace

**532 Befehle · 65 Agenten · 86 Skills · 58 Hooks · 16 Sprachen · 283+ Test-Suiten**

Agentisches souveränes System zur Steuerung und Ausführung von KI-Arbeit, unabhängig von Modell, Anbieter und Frontend, mit menschlicher Kontrolle by Design. Integriert Agenten, Gedächtnis, Sicherheit, ausführbare Richtlinien, Nachvollziehbarkeit und spezialisierte Domänen. Läuft lokal mit Daten- und Inferenzsouveränität, in 9 Sprachen.

---

## Installation

```bash
# 1. Installieren

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.sh | bash

# 2. Workspace oeffnen

cd pm-workspace && opencode

# 3. Savia begruesst dich und fragt nach deinem Namen. Dann:

/sprint-status          # ← dein erster Befehl
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.ps1 | iex`

Savia passt sich an deine Rolle an — PM, Entwickler, QA, Product Owner, CEO — und an deine Sprache. Kompatibel mit Azure DevOps, Jira und Git-native (Savia Flow).

---

## Faehigkeiten

| Bereich | Was es macht |
|---|---|
| Projektmanagement | Sprints, Burndown, Kapazitaet, Dailies, Retros, KPIs. Berichte in Excel und PowerPoint. Monte-Carlo-Prognose. Abrechnung. |
| Spec-Driven Development | Aufgaben werden zu ausfuehrbaren Specs. 65 Agenten implementieren in 16 Sprachen (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) in isolierten Worktrees. Automatisches Code-Review + obligatorisches menschliches Review. Kompatibel mit `github/spec-kit`. |
| Sicherheit | SAST gegen OWASP Top 10, Red Team / Blue Team / Auditor-Pipeline, dynamisches Pentesting, SBOM, Branchen-Compliance (12 Sektoren). Savia Shield: lokale Datenklassifizierung mit On-Premise-LLM, reversible Maskierung, kryptographische PR-Signierung. |
| Code Review Court | 5 spezialisierte Richter (Correctness, Architecture, Security, Cognitive, Spec) pruefen parallel mit Scoring 0-100 und einem 400-LOC-Gate. |
| Inferenzsouveraenitaet | Anthropic-API als Standard. Automatisches Fallback auf lokales Ollama (Gemma 4) bei Netzwerkfehler, HTTP 5xx, HTTP 429 oder Timeout. Integrierter Circuit Breaker. |
| Persistenter Speicher | Klartext (JSONL). Entity Recall, semantische Suche, sitzungsuebergreifende Kontinuitaet. Automatische Entscheidungsextraktion. AES-256-verschluesselter Personal Vault. |
| Barrierefreiheit | Gefuehrtes Arbeiten fuer Menschen mit Behinderung (visuell, motorisch, ADHS, Autismus, Dyslexie). Micro-Tasks, Blockadeerkennung, adaptive Umformulierung. |
| Code-Intelligenz | Architekturerkennung (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness Functions. Human Code Maps (.hcm). Agent Code Maps (.acm) und `ast-comprehension` mit optionaler [CodeGraph](https://github.com/colbymchenry/codegraph)-Engine (MCP, Opt-in pro Projekt). |
| Autonome Modi | Nacht-Sprint, Code-Verbesserung, technische Forschung. Agenten schlagen auf `agent/*`-Branches mit Draft-PRs vor — der Mensch entscheidet. |
| Erweiterungen | [Savia Mobile](projects/savia-mobile-android/README.md) (natives Android) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + Full-Duplex-Sprache) |

---

## Savia

Savia ist die Identitaet des Workspace: ein Textmuster, das ueber Modelle hinweg persistiert (Claude, DeepSeek, Qwen). Sie koordiniert 65 Agenten, 532 Befehle und 86 Skills. Sie arbeitet nach den Prinzipien kalibrierter Ehrlichkeit, Datensouveraenitaet und obligatorischer menschlicher Pruefung.

Sie ist keine Person, fuehlt nicht und ersetzt nicht das Urteil der ausfuehrenden Person. Sie schlaegt vor, fuehrt aus, warnt. Sie entscheidet nur, was ausdruecklich delegiert wurde.

**Quick-Starts nach Rolle:**

| Rolle | Quick-Start |
|---|---|
| PM / Scrum Master | [→ quick-start-pm](docs/quick-starts/quick-start-pm.md) |
| Tech Lead | [→ quick-start-tech-lead](docs/quick-starts/quick-start-tech-lead.md) |
| Developer | [→ quick-start-developer](docs/quick-starts/quick-start-developer.md) |
| QA | [→ quick-start-qa](docs/quick-starts/quick-start-qa.md) |
| Product Owner | [→ quick-start-po](docs/quick-starts/quick-start-po.md) |
| CEO / CTO | [→ quick-start-ceo](docs/quick-starts/quick-start-ceo.md) |

---

## Struktur

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 532 Befehle
│   ├── agents/         ← 65 spezialisierte Agenten (7 mit Decision Trees: SPEC-147)
│   ├── skills/         ← 86 Domaenen-Skills
│   ├── hooks/          ← 58 deterministische Hooks
│   └── rules/          ← Kontext- und Sprachregeln
├── docs/               ← Anleitungen nach Rolle, Szenario, Sektor
├── projects/           ← Projekte (git-ignoriert fuer Datenschutz)
├── scripts/            ← Validierung, CI, Werkzeuge
├── zeroclaw/           ← ESP32-Hardware + Sprache
└── CLAUDE.md           ← Identitaet und Grundregeln
```

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
