# Erste Schritte — pm-workspace

> Von Null auf produktiv in 15 Minuten.

---

## 1. Voraussetzungen

- **Claude Code / OpenCode** installiert und authentifiziert (`claude --version` oder `opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 fuer PRs und Issues (`gh --version`)
- **jq** fuer JSON-Parsing (`jq --version`)
- (Optional) **Ollama** fuer Savia Shield (`ollama --version`)

## 2. Klonen und erster Start

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

Beim Start erkennt Savia, dass kein Profil existiert, und stellt sich vor. Beantworte ihre Fragen: Name, Rolle, Projekte. Dadurch wird dein Profil in `.claude/profiles/users/{slug}/` erstellt.

Wenn du das Profil ueberspringen willst: gib direkt einen Befehl ein. Savia besteht nicht darauf.

## 3. Dein Projekt einrichten

```bash
/project-new
```

Folge dem Wizard. Savia erkennt dein PM-Tool (Azure DevOps, Jira oder Savia Flow) und erstellt die Struktur in `projects/{name}/`.

Fuer Azure DevOps brauchst du ein PAT in `$HOME/.azure/devops-pat` (eine Zeile, kein Zeilenumbruch). Scopes: Work Items R/W, Project R, Analytics R.

## 4. Hook-Profile (Savia Shield)

Hooks steuern, welche Regeln automatisch ausgefuehrt werden. Es gibt 4 Profile:

| Profil | Was es aktiviert | Wann verwenden |
|--------|-----------------|----------------|
| `minimal` | Nur grundlegende Sicherheit | Demos, erste Schritte |
| `standard` | Sicherheit + Qualitaet | Taegliche Arbeit (Standard) |
| `strict` | Sicherheit + Qualitaet + extra Pruefung | Vor Releases, kritischer Code |
| `ci` | Wie standard, nicht interaktiv | CI/CD-Pipelines |

```bash
# Aktives Profil anzeigen
bash scripts/hook-profile.sh get

# Profil wechseln
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (Datenschutz)

Wenn du mit Kundendaten arbeitest, aktiviere Savia Shield:

```bash
/savia-shield enable
/savia-shield status
```

Shield schuetzt sensible Daten (N4/N4b) davor, in oeffentliche Dateien (N1) zu gelangen. Es arbeitet mit 5 Schichten: Regex, lokales LLM, Post-Write-Audit, reversibles Masking und Base64-Erkennung.

Vollstaendige Anleitung: [docs/savia-shield-guide.de.md](savia-shield-guide.de.md)

## 6. Karten: .scm und .ctx

pm-workspace generiert zwei navigierbare Indizes:

- **`.scm` (Capability Map)**: Katalog von Befehlen, Skills und Agenten, indexiert nach Absicht. Beantwortet "Was kann Savia?".
- **`.ctx` (Context Index)**: Karte, wo welche Information liegt (Regeln, Speicher, Projekte). Beantwortet "Wo suchen oder speichern?".

Beide sind Klartext, automatisch generiert, mit progressivem Laden (L0/L1/L2).

Status: in Vorschlag (SPEC-053, SPEC-054). Wenn verfuegbar, werden sie generiert mit:

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Schnellstart nach Rolle

| Rolle | Erste Befehle | Taegliche Routine |
|-------|---------------|-------------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PRs, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Jede Rolle hat eine detaillierte Anleitung: `docs/quick-starts/quick-start-{rolle}.md`

## 8. Konfigurationsreferenz

| Was konfigurieren | Wo | Beispiel |
|-------------------|-----|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Einzeiliger Token |
| Benutzerprofil | `.claude/profiles/users/{slug}/` | Erstellt von `/profile-setup` |
| Hook-Profil | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Konnektoren | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Projekt PM-Tool | `projects/{name}/CLAUDE.md` | Org URL, Iteration Path |
| Private Konfiguration | `CLAUDE.local.md` (gitignored) | Echte Projekte |

## 9. Performance

- **CLAUDE.md verbraucht Tokens bei jedem Turn** (wird nicht gecacht) — halte sie schlank und unter 150 Zeilen
- **Skills verbrauchen kein Kontext bis sie aufgerufen werden** — viele Skills zu haben ist kostenlos
- **auto-compact loest bei 65%** des Kontextfensters aus — fuehre `/compact` manuell aus, wenn du vorher Verschlechterung bemerkst
- **Speichereintraege sollten < 150 Zeichen sein** — kurze Zusammenfassungen laden schneller und verbrauchen weniger Kontext
- Alle Details: `docs/best-practices-claude-code.md`

## 10. Naechste Schritte

1. Fuehre `/help` aus, um den interaktiven Befehlskatalog zu sehen
2. Fuehre `/daily-routine` aus, damit Savia deine Routine vorschlaegt
3. Lies die Anleitung fuer deine Rolle in `docs/quick-starts/`
4. Wenn du mit Kundendaten arbeitest: aktiviere Savia Shield
5. Wenn etwas nicht funktioniert: `/workspace-doctor` diagnostiziert die Umgebung

---

> Detaillierte Dokumentation: `docs/readme/` (13 Abschnitte) und `docs/guides/` (15 Anleitungen nach Szenario).
