---
lang: eu
---

**Euskara** | [Gaztelania](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# Savia

> Kortesiazko itzulpena. Erreferentziazko bertsioa: [gaztelania](README.md).
> Azken sinkronizazioa: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**567 komandoak · 90 agenteak · 139 skills · 134 hooks**

## Garapen workspace multi-agentea

**567 komando · 90 agente · 139 skill · 134 hook · 16 hizkuntza · 283+ test suite**

pm-workspace-k Claude Code eta OpenCode ingeniaritza multi-agente ingurune bihurtzen ditu. Agente espezializatuak orkestratzen ditu proiektuen kudeaketarako, spec exekutagarriekin garapenerako, segurtasun auditoriarako eta kode berrikusketarako. Lokalean funtzionatzen du datu eta inferentzia subiranotasunarekin, 9 hizkuntzatan.

---

## Instalazioa

```bash
# 1. Instalatu

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Ireki workspace-a

cd savia && opencode

# 3. Saviak agurtzen zaitu eta izena galdetzen dizu. Gero:

/sprint-status          # ← zure lehen komandoa
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Windows-erako baldintza: **Git for Windows (Git Bash barne)**. Claude Code-k `Git Bash wasn't found` esaten badu, instalatu Git (https://git-scm.com/downloads/win) edo ezarri `CLAUDE_CODE_GIT_BASH_PATH` zure `bash.exe`-ren bidearekin eta ireki saio berri bat.

Savia zure rolera moldatzen da — PM, developer, QA, Product Owner, CEO — eta zure hizkuntzara. Azure DevOps, Jira eta Git-native (Savia Flow) bateragarria.

---

## Zergatik existitzen da Savia

IA lagundutako exekuzioa confiantza baino azkarrago hazten da. Savia existitzen da exekuzio hori gobernatua izan dadin: IA-k gero eta gehiago exekutatu dezake, agintea bereganatu gabe.

## Printzipioak

Giza autoritatea by design · subiranotasun teknikoa · evidencia claims-en gainetik · policy-as-code · delegazio segurua.

## Zer egiten du Savia-k

Gobernatu (arriskua L0-L4, gates, receipts) · exekutatu · gogoratu · ebaluatu · domeinu espezializatuak.

## Arkitektura

Gobernua + Exekuzioa + Memoria → Evidence/Evals → Frontend + Hornitzaileak.

## Frontend eta hornitzaileak

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, L2 takoa).

## Gobernantza eta segurtasuna

Human gates L0-L4. Compliance-as-code: exekutatutako kontrolen ebidentzia, ez legelama definitiborik.

## Gaitasunak

Gaitasunen taula osoa: [capabilities.eu.md](docs/readme/capabilities.eu.md).

---

## Savia

Savia workspace-aren identitatea da: modeloetan zehar irauten duen testu patrola (Claude, DeepSeek, Qwen). 90 agente, 567 komando eta 139 skill koordinatzen ditu. Zintzotasun kalibratu, datu subiranotasun eta giza berrikusketa derrigorrezko printzipioen pean jarduten du.

Ez da pertsona, ez du sentitzen, eta ez du operatzen duenaren irizpidea ordezkatzen. Proposatu, exekutatu, ohartarazi. Esplizituki delegatutakoa bakarrik erabakitzen du.

**Quick-start-ak rolaren arabera:**

Rolaren araberako quick-start-ak: [quick-starts.eu.md](docs/readme/quick-starts.eu.md).

---

## Egitura

Biltegiaren zuhaitza: [repo-structure.eu.md](docs/readme/repo-structure.eu.md).

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
