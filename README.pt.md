<!-- Header image removed per SE-259 S2 -->

**Portugues** | [Espanhol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

# PM-Workspace

> Traducao de cortesia. Versao de referencia: [espanhol](README.md).
> Ultima sincronizacao: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Workspace de desenvolvimento multi-agente

**567 comandos · 89 agentes · 136 skills · 124 hooks**

Sistema agêntico soberano para governar e executar trabalho com IA, independente de modelo, provedor e frontend, com critério humano por design. Integra agentes, memória, segurança, políticas executáveis, rastreabilidade e domínios especializados. Funciona localmente com soberania de dados e inferência, em 9 idiomas.

---

## Instalacao

```bash
# 1. Instale

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Abra o workspace

cd savia && opencode

# 3. A Savia cumprimenta-o e pergunta o seu nome. Depois:

/sprint-status          # ← o seu primeiro comando
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

A Savia adapta-se ao seu papel — PM, developer, QA, Product Owner, CEO — e ao seu idioma. Compativel com Azure DevOps, Jira e Git-native (Savia Flow).

---

## Por que existe a Savia

A execução assistida por IA cresce mais rápido que a confiança sobre ela. A Savia existe para que essa execução seja governada: a IA pode assumir progressivamente mais execução sem se apropriar da autoridade.

## Princípios

Autoridade humana por design · soberania com significado técnico · evidência sobre claims · policy-as-code · delegação segura.

## O que a Savia faz

Governar (risco L0-L4, gates, receipts) · executar (agents, commands, skills, SDD) · lembrar (memória bitemporal) · avaliar (evals com baseline) · domínios especializados.

## Arquitetura

Governança (Policy/Risk/Gates) + Execução (Agents/Skills/Tools) + Memória (Context/Knowledge/History) → Evidence/Evals → Frontends + Providers.

## Frontends e provedores

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, teto L2). Independência de modelo e provedor por design.

## Governança e segurança

Human gates por nível de risco (L0-L4). Compliance-as-code como direção: a Savia produz evidência de controles executados; não declara conformidade legal definitiva.

## Capacidades

| Area | O que faz |
|---|---|
| Gestao de projetos | Sprints, burndown, capacidade, dailies, retros, KPIs. Relatorios em Excel e PowerPoint. Previsao com Monte Carlo. Faturacao. |
| Spec-Driven Development | Tarefas convertem-se em specs executaveis. 89 agentes implementam em 16 linguagens (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) em worktrees isolados. Code review automatico + revisao humana obrigatoria. Compativel com `github/spec-kit`. |
| Seguranca | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinamico, SBOM, compliance setorial (12 setores). Savia Shield: classificacao local de dados com LLM on-premise, mascaramento reversivel, assinatura criptografica de PRs. |
| Code Review Court | 5 juizes especializados (correctness, architecture, security, cognitive, spec) revisam em paralelo com scoring 0-100 e gate de 400 LOC. |
| Soberania de inferencia | API Anthropic por default. Fallback automatico para Ollama local (Gemma 4) em caso de erro de rede, HTTP 5xx, HTTP 429 ou timeout. Circuit breaker integrado. |
| Memoria persistente | Texto simples (JSONL). Entity recall, pesquisa semantica, continuidade entre sessoes. Extracao automatica de decisoes. Personal Vault cifrado AES-256. |
| Acessibilidade | Trabalho guiado para pessoas com deficiencia (visual, motora, TDAH, autismo, dislexia). Micro-tarefas, detecao de bloqueios, reformulacao adaptativa. |
| Inteligencia de codigo | Detecao de arquitetura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) e `ast-comprehension` com motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in por projeto). |
| Modos autonomos | Sprint noturno, melhoria de codigo, investigacao tecnica. Agentes propoem em branches `agent/*` com PRs Draft — o humano decide. |
| Extensoes | [Savia Mobile](projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + voz full-duplex) |

---

## Savia

A Savia e a identidade do workspace: um padrao de texto que persiste atraves de modelos (Claude, DeepSeek, Qwen). Coordena 89 agentes, 567 comandos e 136 skills. Opera sob principios de honestidade calibrada, soberania de dados e revisao humana obrigatoria.

Nao e uma pessoa, nao sente, e nao substitui o criterio de quem opera. Propoe, executa, adverte. Decide apenas o que e explicitamente delegado.

**Quick-starts por papel:**

| Papel | Quick-start |
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
│   ├── agents/         ← 89 agentes especializados (7 com decision trees: SPEC-147)
│   ├── skills/         ← 136 skills de dominio
│   ├── hooks/          ← 124 hooks deterministicos
│   └── rules/          ← regras de contexto e linguagem
├── docs/               ← guias por papel, cenario, setor
├── projects/           ← projetos (git-ignorados por privacidade)
├── scripts/            ← validacao, CI, utilitarios
├── zeroclaw/           ← hardware ESP32 + voz
└── CLAUDE.md           ← identidade e regras fundamentais
```

---

## Documentacao

| Secao | Descricao |
|---|---|
| [Guia de inicio](docs/getting-started.md) | De zero a produtivo |
| [Fluxo de dados](docs/data-flow-guide-es.md) | Como as partes se conectam |
| [Confidencialidade](docs/confidentiality-levels.md) | 5 niveis (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Soberania de dados |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandos e agentes](docs/readme/12-comandos-agentes.md) | Referencia completa |
| [Guias por cenario](docs/guides/README.md) | Azure, Jira, startup, saude... |
| [Adocao](docs/ADOPTION_GUIDE.md) | Passo a passo para consultoras |

---

## Principios

1. **Texto simples e a verdade** — .md e .jsonl. Sem IA, os dados continuam legiveis
2. **Privacidade absoluta** — os dados do utilizador nunca saem da sua maquina
3. **O humano decide** — a IA propoe, nunca merge nem deploy autonomo
4. **MIT** — sem vendor lock-in, sem telemetria

---

## Contribuir

Leia [CONTRIBUTING.md](CONTRIBUTING.md) e [SECURITY.md](SECURITY.md). PRs bem-vindos.

## Licenca

[MIT](LICENSE) — Criado por [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
