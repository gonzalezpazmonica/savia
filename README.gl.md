---
lang: gl
---

**Galego** | [Castelan](README.md) | [English](README.en.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Traducion de cortesia. Version de referencia: [espanol](README.md).
> Ultima sincronizacion: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Workspace de desenvolvemento multi-axente

**567 comandos · 90 axentes · 139 skills · 134 hooks**

Sistema axente soberano para gobernar e executar traballo con IA, independente de modelo, provedor e frontend, con criterio humano por deseño. Integra axentes, memoria, seguridade, políticas executables, trazabilidade e dominios especializados. Funciona en local con soberanía de datos e inferencia, en 9 idiomas.

---

## Instalacion

```bash
# 1. Instala

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Abre o workspace

cd savia && opencode

# 3. Savia saudate e preguntache o nome. Despois:

/sprint-status          # ← o teu primeiro comando
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Requisito en Windows: **Git for Windows (inclúe Git Bash)**. Se Claude Code di `Git Bash wasn't found`, instala Git (https://git-scm.com/downloads/win) ou fixa `CLAUDE_CODE_GIT_BASH_PATH` coa ruta do teu `bash.exe` e abre unha sesión nova.

Savia adaptase ao teu rol — PM, developer, QA, Product Owner, CEO — e a tua lingua. Compatible con Azure DevOps, Jira e Git-native (Savia Flow).

---

## Por que existe Savia

A execución asistida por IA crece máis rápido que a confianza sobre ela. Savia existe para que esa execución sexa gobernada: a IA pode asumir progresivamente máis execución sen apropiarse da autoridade.

## Principios

Autoridade humana por deseño · soberanía con significado técnico · evidencia sobre claims · policy-as-code · delegación segura.

## Que fai Savia

Gobernar (risco L0-L4, gates, receipts) · executar (agents, commands, skills, SDD) · recordar (memoria bitemporal) · avaliar (evals con baseline) · dominios especializados.

## Arquitectura

Goberno (Policy/Risk/Gates) + Execución (Agents/Skills/Tools) + Memoria (Context/Knowledge/History) → Evidence/Evals → Frontends + Providers.

## Frontends e provedores

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, teito L2). Independencia de modelo e provedor por deseño.

## Gobernanza e seguridade

Human gates por nivel de risco (L0-L4). Compliance-as-code como dirección: Savia produce evidencia de controls executados; non declara cumprimento legal definitivo.

## Capacidades

Táboa completa de capacidades: [capabilities.gl.md](docs/readme/capabilities.gl.md).

---

## Savia

Savia e a identidade do workspace: un patron de texto que persiste a traves de modelos (Claude, DeepSeek, Qwen). Coordina 90 axentes, 567 comandos e 139 skills. Opera baixo principios de honestidade calibrada, soberania de datos e revision humana obrigatoria.

Non e unha persoa, non sente, e non substitue o criterio de quen opera. Propon, executa, advirte. Decide so o delegado explicitamente.

**Quick-starts por rol:**

Quick-starts por rol: [quick-starts.gl.md](docs/readme/quick-starts.gl.md).

---

## Estrutura

Árbore do repositorio: [repo-structure.gl.md](docs/readme/repo-structure.gl.md).

---

## Documentacion

| Seccion | Descricion |
|---|---|
| [Guia de inicio](docs/getting-started.md) | De cero a produtivo |
| [Fluxo de datos](docs/data-flow-guide-es.md) | Como se conectan as partes |
| [Confidencialidade](docs/confidentiality-levels.md) | 5 niveis (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Soberania de datos |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandos e axentes](docs/readme/12-comandos-agentes.md) | Referencia completa |
| [Guias por escenario](docs/guides/README.md) | Azure, Jira, startup, sanidade... |
| [Adopcion](docs/ADOPTION_GUIDE.md) | Paso a paso para consultoras |

---

## Principios

1. **O texto plano e a verdade** — .md e .jsonl. Sen IA, os datos seguen lexibeis
2. **Privacidade absoluta** — os datos do usuario nunca saen da sua maquina
3. **O humano decide** — a IA propon, nunca merge nin deploy autonomo
4. **MIT** — sen vendor lock-in, sen telemetria

---

## Contribuir

Le [CONTRIBUTING.md](CONTRIBUTING.md) e [SECURITY.md](SECURITY.md). PRs benvidos.

## Licenza

[MIT](LICENSE) — Creado por [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
