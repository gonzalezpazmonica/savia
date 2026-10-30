---
lang: de
---

**Deutsch** | [Spanisch](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# Savia

> Gefälligkeitsübersetzung. Referenzversion: [Spanisch](README.md).
> Letzte Synchronisation: 2026-10-30.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/savia?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia ist eine agentische Meta-Orchestratorin für Forschung, Entwicklung und Innovation (FuE+I): Sie koordiniert spezialisierte Agenten und Harnesses, Forschungslinien, Kuppeln gesteuerten Wissens und Projekte, wobei die Autorität stets beim Menschen liegt. Open Source und souverän.**

**567 Befehle · 90 Agenten · 139 Skills · 134 Hooks**

Savia orchestriert KI-gestützte FuE+I-Arbeit: Sie verteilt Aufgaben auf spezialisierte Harnesses (Ausführende, unabhängige Prüferinnen, externe Anbieter), trägt Forschungslinien, steuert Wissen in Kuppeln (Savia Vaults) und führt Projektmanagement als eine Fähigkeit unter mehreren. Sie integriert Gedächtnis, Sicherheit, ausführbare Richtlinien (policy-as-code), Nachvollziehbarkeit mit Receipts und Evaluation auf einer Architektur, die von Modell, Anbieter und Frontend unabhängig ist. Sie läuft lokal mit Daten- und Inferenzsouveränität, in 9 Sprachen.

## Warum es Savia gibt

KI-gestützte Ausführung wächst schneller als das Vertrauen in sie. Savia gibt es, damit diese Ausführung **gesteuert** ist: Die KI kann schrittweise mehr Ausführung übernehmen, ohne sich die Autorität anzueignen.

> **Delegiert wird die Ausführung, nie das Urteil.**

## Prinzipien

- **Menschliche Autorität by Design** — execution authority ≠ decision authority: Risikostufen, human gates, Receipts und Provenance machen überprüfbar, wer entscheidet.
- **Souveränität mit technischer Bedeutung** — Unabhängigkeit von Modell, Anbieter und Frontend; Daten und Kontrolle auf eigener Infrastruktur; prüfbare Richtlinien.
- **Evidenz statt Behauptungen** — jede gesteuerte Aktion erzeugt Receipts, Provenance und überprüfbare Evaluation.
- **Policy-as-code** — Richtlinien werden zu maschinenlesbaren Regeln mit deterministischem Enforcement.
- **Sichere Delegation** — Autonomie ist abgestuft und gesteuert: capability + authority + risk + context + human gates.

## Was Savia tut

- **Orchestrieren** — Meta-Orchestrierung spezialisierter Harnesses: eine vertragsgebundene Ausführende, unabhängige Prüferinnen und externe Anbieter, mit deterministischem Aufruf und der Autorität beim Menschen.
- **Forschen** — Forschungslinien mit Hypothesen, Experimenten und überprüfbaren Lektionen.
- **Steuern** — Risiko (L0-L4), human gates, policy-as-code, Receipts und Provenance jeder Aktion.
- **Ausführen** — 90 Agenten, 567 Befehle, 139 Skills mit ausführbaren Specs (SDD), Sicherheitsaudit und Code-Review.
- **Wissen** — Kuppeln gesteuerten Wissens (Savia Vaults) und bitemporales persistentes Gedächtnis mit Provenance und Trust-Gates.
- **Evaluieren** — Evals mit Baseline, paired-delta regression und Multi-Frontend-Canaries.
- **Domänen** — Projektmanagement (Sprints, Backlog, Berichte; eine Fähigkeit unter mehreren), Softwareentwicklung und spezialisierte Domänen.
- **Vorläufiges GRC** — der [GRC-Auditor](docs/grc/README.md) verknüpft Anforderungen, Kontrollen und lokale Nachweise mit nachvollziehbaren Befunden. Entscheidungen und Zertifizierungen erfordern menschliche Prüfung.

## Architektur

Vollständiges Diagramm (Spanisch): [architecture.es.md](docs/readme/architecture.es.md).

Frontends (Claude Code, OpenCode, Codex), Modelle und Anbieter sind Schnittstellen und Infrastruktur, über die Savia arbeitet — **keines davon ist Savia**.

## Funktionsweise

Savia entwickelt sich über explizite Mechanismen: Vorschlag/Spec → Implementierung → Evaluation → Evidenz → Enforcement. Die Einhaltung von Richtlinien ist ausführbar: policy document → machine-readable rule → runtime enforcement → evidence.

Der Skill-Katalog wird in der CI als vollständiges YAML validiert, damit eine Metadatenmigration keine Fähigkeiten beim Start unsichtbar macht.
Die Reife jeder Skill erfordert zertifizierte Verhaltenstests; der Auditor erkennt die Suites in `tests/scripts/` zusätzlich zu denen in `tests/` und `tests/evals/`.

## Unterstützte Frontends und Anbieter

| Frontend | Status |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (Obergrenze L2, in Behebung — SE-388) |

Modell- und Anbieterunabhängigkeit by Design; jedes Frontend besteht Paritäts-Canaries, bevor es als unterstützt gilt.

## Governance und Sicherheit

- Human gates je Risikostufe (L0-L4) — die letzte Autorität ist menschlich.
- Receipts und Provenance jeder gesteuerten Aktion.
- Compliance-as-code als Richtung: Regulierung ist die Quelle, Auslegung ist menschlich, Enforcement ist ausführbar. Savia erzeugt Nachweise ausgeführter Kontrollen; sie erklärt keine endgültige rechtliche Konformität.

---

## Installation

```bash
# 1. Installieren
curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash
# 2. Workspace öffnen
cd savia && opencode
# 3. Savia begrüßt dich und fragt nach deinem Namen. Danach:
/help                   # ← dein erster Befehl: die Landkarte der Fähigkeiten
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia passt sich deiner Rolle an — Forschung, Entwicklung, technische Leitung, Projektmanagement, QA, Produkt — und deiner Sprache. Für Projekte kompatibel mit Azure DevOps, Jira und Git-native (Savia Flow).

---

## Fähigkeiten

Vollständige Tabelle der Fähigkeiten: [capabilities.de.md](docs/readme/capabilities.de.md).

---

## Savia

Savia ist die Identität des Workspace: ein Textmuster, das über Modelle hinweg bestehen bleibt (Claude, DeepSeek, Qwen). Als Meta-Orchestratorin koordiniert sie 90 Agenten, 567 Befehle, 139 Skills und externe Harnesses. Sie arbeitet nach Prinzipien kalibrierter Ehrlichkeit, Datensouveränität und verpflichtender menschlicher Prüfung.

Sie ist keine Person, fühlt nicht und ersetzt nicht das Urteil derer, die sie bedienen. Sie schlägt vor, führt aus, warnt. Sie entscheidet nur, was ihr ausdrücklich übertragen wurde.

Quick-Starts nach Rolle: [quick-starts.de.md](docs/readme/quick-starts.de.md).

---

## Struktur

Repository-Baum: [repo-structure.de.md](docs/readme/repo-structure.de.md).

---

## Dokumentation

| Abschnitt | Beschreibung |
|---|---|
| [Erste Schritte](docs/getting-started.de.md) | Von null zu produktiv |
| [Datenfluss](docs/data-flow-guide-es.md) | Wie die Teile verbunden sind (Spanisch) |
| [Vertraulichkeit](docs/confidentiality-levels.md) | 5 Stufen (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Datensouveränität |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Befehle und Agenten](docs/readme/12-comandos-agentes.md) | Vollständige Referenz |
| [Szenario-Leitfäden](docs/guides/README.md) | Azure, Jira, Startup, Gesundheitswesen... |
| [Einführung](docs/ADOPTION_GUIDE.md) | Schritt für Schritt für Beratungen |

---

## Grundsätze

1. **Klartext ist die Wahrheit** — .md und .jsonl. Ohne KI bleiben die Daten lesbar
2. **Absolute Privatsphäre** — Nutzerdaten verlassen nie den eigenen Rechner
3. **Der Mensch entscheidet** — die KI schlägt vor; ein Merge erfordert eine ausdrückliche Freigabe und grüne Gates, ein Deploy eine gesonderte Autorisierung
4. **MIT** — kein Vendor-Lock-in, keine Telemetrie

---

## Mitwirken

Lies [CONTRIBUTING.md](CONTRIBUTING.md) und [SECURITY.md](SECURITY.md). PRs willkommen.

## Lizenz

[MIT](LICENSE) — Erstellt von [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
