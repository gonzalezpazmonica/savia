---
lang: gl
---

<!-- Header image removed per SE-259 S2 -->

**Galego** | [Castelan](README.md) | [English](README.en.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Traducion de cortesia. Version de referencia: [espanol](README.md).
> Ultima sincronizacion: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/pm-workspace/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Workspace de desenvolvemento multi-axente

**532 comandos · 65 axentes · 86 skills · 58 hooks · 16 linguaxes · 283+ suites de test**

Sistema axente soberano para gobernar e executar traballo con IA, independente de modelo, provedor e frontend, con criterio humano por deseño. Integra axentes, memoria, seguridade, políticas executables, trazabilidade e dominios especializados. Funciona en local con soberanía de datos e inferencia, en 9 idiomas.

---

## Instalacion

```bash
# 1. Instala

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.sh | bash

# 2. Abre o workspace

cd pm-workspace && opencode

# 3. Savia saudate e preguntache o nome. Despois:

/sprint-status          # ← o teu primeiro comando
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/pm-workspace/main/install.ps1 | iex`

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

| Area | Que fai |
|---|---|
| Xestion de proxectos | Sprints, burndown, capacidade, dailies, retros, KPIs. Informes en Excel e PowerPoint. Prediccion con Monte Carlo. Facturacion. |
| Spec-Driven Development | Tarefas convirtense en specs executabeis. 65 axentes implementan en 16 linguaxes (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) en worktrees illados. Code review automatico + revision humana obrigatoria. Compatible con `github/spec-kit`. |
| Seguridade | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamico, SBOM, compliance sectorial (12 sectores). Savia Shield: clasificacion local de datos con LLM on-premise, enmascaramento reversibel, sinatura criptografica de PRs. |
| Code Review Court | 5 xuices especializados (correctness, architecture, security, cognitive, spec) revisan en paralelo con scoring 0-100 e gate de 400 LOC. |
| Soberania de inferencia | API Anthropic por defecto. Fallback automatico a Ollama local (Gemma 4) en caso de erro de rede, HTTP 5xx, HTTP 429 ou timeout. Circuit breaker integrado. |
| Memoria persistente | Texto plano (JSONL). Entity recall, busca semantica, continuidade entre sesions. Extraccion automatica de decisions. Personal Vault cifrado AES-256. |
| Accesibilidade | Traballo guiado para persoas con discapacidade (visual, motora, TDAH, autismo, dislexia). Micro-tarefas, deteccion de bloqueos, reformulacion adaptativa. |
| Intelixencia de codigo | Deteccion de arquitectura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) e `ast-comprehension` con motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in por proxecto). |
| Modos autonomos | Sprint nocturno, mellora de codigo, investigacion tecnica. Axentes proponen en ramas `agent/*` con PRs Draft — o humano decide. |
| Extensions | [Savia Mobile](projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + voz full-duplex) |

---

## Savia

Savia e a identidade do workspace: un patron de texto que persiste a traves de modelos (Claude, DeepSeek, Qwen). Coordina 65 axentes, 532 comandos e 86 skills. Opera baixo principios de honestidade calibrada, soberania de datos e revision humana obrigatoria.

Non e unha persoa, non sente, e non substitue o criterio de quen opera. Propon, executa, advirte. Decide so o delegado explicitamente.

**Quick-starts por rol:**

| Rol | Quick-start |
|---|---|
| PM / Scrum Master | [→ quick-start-pm](docs/quick-starts/quick-start-pm.md) |
| Tech Lead | [→ quick-start-tech-lead](docs/quick-starts/quick-start-tech-lead.md) |
| Developer | [→ quick-start-developer](docs/quick-starts/quick-start-developer.md) |
| QA | [→ quick-start-qa](docs/quick-starts/quick-start-qa.md) |
| Product Owner | [→ quick-start-po](docs/quick-starts/quick-start-po.md) |
| CEO / CTO | [→ quick-start-ceo](docs/quick-starts/quick-start-ceo.md) |

---

## Estrutura

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 567 comandos
│   ├── agents/         ← 65 axentes especializados (7 con decision trees: SPEC-147)
│   ├── skills/         ← 86 skills de dominio
│   ├── hooks/          ← 58 hooks deterministas
│   └── rules/          ← regras de contexto e linguaxe
├── docs/               ← guias por rol, escenario, sector
├── projects/           ← proxectos (git-ignorados por privacidade)
├── scripts/            ← validacion, CI, utilidades
├── zeroclaw/           ← hardware ESP32 + voz
└── CLAUDE.md           ← identidade e regras fundamentais
```

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
