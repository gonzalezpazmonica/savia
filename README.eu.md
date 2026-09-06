---
lang: eu
---

<!-- Header image removed per SE-259 S2 -->

**Euskara** | [Gaztelania](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Kortesiazko itzulpena. Erreferentziazko bertsioa: [gaztelania](README.md).
> Azken sinkronizazioa: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/pm-workspace/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Garapen workspace multi-agentea

**532 komando · 65 agente · 86 skill · 58 hook · 16 hizkuntza · 283+ test suite**

pm-workspace-k Claude Code eta OpenCode ingeniaritza multi-agente ingurune bihurtzen ditu. Agente espezializatuak orkestratzen ditu proiektuen kudeaketarako, spec exekutagarriekin garapenerako, segurtasun auditoriarako eta kode berrikusketarako. Lokalean funtzionatzen du datu eta inferentzia subiranotasunarekin, 9 hizkuntzatan.

---

## Instalazioa

```bash
# 1. Instalatu

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.sh | bash

# 2. Ireki workspace-a

cd pm-workspace && opencode

# 3. Saviak agurtzen zaitu eta izena galdetzen dizu. Gero:

/sprint-status          # ← zure lehen komandoa
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.ps1 | iex`

Savia zure rolera moldatzen da — PM, developer, QA, Product Owner, CEO — eta zure hizkuntzara. Azure DevOps, Jira eta Git-native (Savia Flow) bateragarria.

---

## Gaitasunak

| Arloa | Zer egiten duen |
|---|---|
| Proiektuen kudeaketa | Sprint-ak, burndown-a, ahalmena, dailyak, retroak, KPIak. Excel eta PowerPoint txostenak. Monte Carlo iragarpena. Fakturazioa. |
| Spec-Driven Development | Zereginak spec exekutagarri bihurtzen dira. 65 agentek 16 hizkuntzatan inplementatzen dute (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) worktree isolatuetan. Kode berrikusketa automatikoa + giza berrikusketa derrigorrezkoa. `github/spec-kit` bateragarria. |
| Segurtasuna | SAST OWASP Top 10-aren aurka, Red Team / Blue Team / Auditor pipeline-a, pentesting dinamikoa, SBOM, sektore-compliance (12 sektore). Savia Shield: datuen sailkapen lokala on-premise LLMarekin, maskaratze itzulgarria, PR sinadura kriptografikoa. |
| Code Review Court | 5 epaile espezializatu (correctness, architecture, security, cognitive, spec) paraleloan berrikusten dute 0-100 puntuazioarekin eta 400 LOC gatearekin. |
| Inferentzia subiranotasuna | Anthropic API lehenespenez. Ollama lokalera (Gemma 4) fallback automatikoa sare errorea, HTTP 5xx, HTTP 429 edo timeout kasuetan. Circuit breaker integratua. |
| Memoria iraunkorra | Testu arrunta (JSONL). Entity recall, bilaketa semantikoa, saioen arteko jarraitutasuna. Erabakien erauzketa automatikoa. Personal Vault AES-256 zifratua. |
| Irisgarritasuna | Lan gidatua desgaitasunak dituzten pertsonentzat (ikusmena, motorra, AGAH, autismoa, dislexia). Mikro-zereginak, blokeoen detekzioa, birformulatze moldagarria. |
| Kode adimena | Arkitektura detekzioa (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) eta `ast-comprehension` [CodeGraph](https://github.com/colbymchenry/codegraph) motor aukerakoarekin (MCP, proiektuko opt-in). |
| Modu autonomoak | Gaueko sprint-a, kode hobekuntza, ikerketa teknikoa. Agenteek `agent/*` adarretan proposatzen dute Draft PR-ekin — gizakiak erabakitzen du. |
| Luzapenak | [Savia Mobile](projects/savia-mobile-android/README.md) (Android natiboa) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + ahots full-duplex) |

---

## Savia

Savia workspace-aren identitatea da: modeloetan zehar irauten duen testu patrola (Claude, DeepSeek, Qwen). 65 agente, 532 komando eta 86 skill koordinatzen ditu. Zintzotasun kalibratu, datu subiranotasun eta giza berrikusketa derrigorrezko printzipioen pean jarduten du.

Ez da pertsona, ez du sentitzen, eta ez du operatzen duenaren irizpidea ordezkatzen. Proposatu, exekutatu, ohartarazi. Esplizituki delegatutakoa bakarrik erabakitzen du.

**Quick-start-ak rolaren arabera:**

| Rola | Quick-start |
|---|---|
| PM / Scrum Master | [→ quick-start-pm](docs/quick-starts/quick-start-pm.md) |
| Tech Lead | [→ quick-start-tech-lead](docs/quick-starts/quick-start-tech-lead.md) |
| Developer | [→ quick-start-developer](docs/quick-starts/quick-start-developer.md) |
| QA | [→ quick-start-qa](docs/quick-starts/quick-start-qa.md) |
| Product Owner | [→ quick-start-po](docs/quick-starts/quick-start-po.md) |
| CEO / CTO | [→ quick-start-ceo](docs/quick-starts/quick-start-ceo.md) |

---

## Egitura

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 532 komando
│   ├── agents/         ← 65 agente espezializatu (7 decision tree-rekin: SPEC-147)
│   ├── skills/         ← 86 domeinu skill
│   ├── hooks/          ← 58 hook deterministiko
│   └── rules/          ← testuinguru eta hizkuntza arauak
├── docs/               ← gidak rolaren, eszenarioaren, sektorearen arabera
├── projects/           ← proiektuak (git-ignoratuak pribatutasunagatik)
├── scripts/            ← balidazioa, CI, tresnak
├── zeroclaw/           ← ESP32 hardwarea + ahotsa
└── CLAUDE.md           ← identitatea eta oinarrizko arauak
```

---

## Dokumentazioa

| Atala | Deskribapena |
|---|---|
| [Hasteko gida](docs/getting-started.md) | Zerotik produktibora |
| [Datu-fluxua](docs/data-flow-guide-es.md) | Nola konektatzen diren atalak |
| [Konfidentzialtasuna](docs/confidentiality-levels.md) | 5 maila (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Datuen subiranotasuna |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Komandoak eta agenteak](docs/readme/12-comandos-agentes.md) | Erreferentzia osoa |
| [Eszenario-gidak](docs/guides/README.md) | Azure, Jira, startup, osasuna... |
| [Adopzioa](docs/ADOPTION_GUIDE.md) | Pausoz pauso aholkularitzentzat |

---

## Printzipioak

1. **Testu arrunta da egia** — .md eta .jsonl. IArik gabe, datuak irakurgarriak izaten jarraitzen dute
2. **Pribatutasun absolutua** — erabiltzailearen datuak ez dira inoiz bere makinatik irteten
3. **Gizakiak erabakitzen du** — IAk proposatzen du, inoiz ez merge edo deploy autonomoa
4. **MIT** — vendor lock-in gabe, telemetria gabe

---

## Lagundu

Irakurri [CONTRIBUTING.md](CONTRIBUTING.md) eta [SECURITY.md](SECURITY.md). PR-ak ongi etorriak.

## Lizentzia

[MIT](LICENSE) — [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)-ek sortua
