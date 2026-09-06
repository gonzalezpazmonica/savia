---
lang: en
---

<!-- Header image removed per SE-259 S2 -->

**English** | [Español](README.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Català](README.ca.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Courtesy translation. Reference version: [Spanish](README.md).
> Last sync: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Multi-agent development workspace

**567 commands · 89 agents · 136 skills · 124 hooks**

pm-workspace turns Claude Code and OpenCode into a multi-agent engineering environment. It orchestrates specialized agents for project management, spec-driven development, security auditing, and code review. Runs locally with data and inference sovereignty, in 9 languages.

---

## Install

```bash
# 1. Install

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Open the workspace

cd savia && opencode

# 3. Savia greets you and asks your name. Then:

/sprint-status          # ← your first command
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia adapts to your role — PM, developer, QA, Product Owner, CEO — and your language. Works with Azure DevOps, Jira, and Git-native (Savia Flow).

---

## Why Savia exists

AI-assisted execution is growing faster than trust in it. Savia exists so that this execution is governed: the AI can progressively take on more execution without appropriating authority.

## Principles

Human authority by design · sovereignty with technical meaning · evidence over claims · policy-as-code · safe delegation.

## What Savia does

Govern (risk L0-L4, gates, receipts) · execute (agents, commands, skills, SDD) · remember (bitemporal memory) · evaluate (baseline evals) · specialized domains.

## Architecture

Governance (Policy/Risk/Gates) + Execution (Agents/Skills/Tools) + Memory (Context/Knowledge/History) → Evidence/Evals → Frontends + Providers.

## Frontends and providers

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, L2 ceiling). Model and provider independence by design.

## Governance and safety

Human gates per risk level (L0-L4). Compliance-as-code as a direction: Savia produces evidence of executed controls; it does not declare definitive legal compliance.

## Capabilities

| Area | What it does |
|---|---|
| Project management | Sprints, burndown, capacity, dailies, retros, KPIs. Excel and PowerPoint reports. Monte Carlo forecasting. Billing. |
| Spec-Driven Development | Tasks become executable specs. 89 agents implement in 16 languages (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) in isolated worktrees. Automated code review + mandatory human review. Compatible with `github/spec-kit`. |
| Security | SAST against OWASP Top 10, Red Team / Blue Team / Auditor pipeline, dynamic pentesting, SBOM, sector compliance (12 sectors). Savia Shield: local data classification with on-premise LLM, reversible masking, cryptographic PR signing. |
| Code Review Court | 5 specialized judges (correctness, architecture, security, cognitive, spec) review in parallel with 0-100 scoring and a 400 LOC gate. |
| Inference sovereignty | Anthropic API by default. Automatic fallback to local Ollama (Gemma 4) on network error, HTTP 5xx, HTTP 429, or timeout. Integrated circuit breaker. |
| Persistent memory | Plain text (JSONL). Entity recall, semantic search, cross-session continuity. Automatic decision extraction. AES-256 encrypted Personal Vault. |
| Accessibility | Guided work for people with disabilities (visual, motor, ADHD, autism, dyslexia). Micro-tasks, block detection, adaptive reformulation. |
| Code intelligence | Architecture detection (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) and `ast-comprehension` with optional [CodeGraph](https://github.com/colbymchenry/codegraph) engine (MCP, opt-in per project). |
| Autonomous modes | Overnight sprint, code improvement, tech research. Agents propose on `agent/*` branches with Draft PRs — the human decides. |
| Extensions | [Savia Mobile](projects/savia-mobile-android/README.md) (native Android) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + full-duplex voice) |

---

## Savia

Savia is the identity of the workspace: a text pattern that persists across models (Claude, DeepSeek, Qwen). She coordinates 89 agents, 567 commands, and 136 skills. She operates under principles of calibrated honesty, data sovereignty, and mandatory human review.

She is not a person, does not feel, and does not replace the operator's judgment. She proposes, executes, warns. She only decides what is explicitly delegated.

**Quick-starts by role:**

| Role | Quick-start |
|---|---|
| PM / Scrum Master | [→ quick-start-pm](docs/quick-starts/quick-start-pm.md) |
| Tech Lead | [→ quick-start-tech-lead](docs/quick-starts/quick-start-tech-lead.md) |
| Developer | [→ quick-start-developer](docs/quick-starts/quick-start-developer.md) |
| QA | [→ quick-start-qa](docs/quick-starts/quick-start-qa.md) |
| Product Owner | [→ quick-start-po](docs/quick-starts/quick-start-po.md) |
| CEO / CTO | [→ quick-start-ceo](docs/quick-starts/quick-start-ceo.md) |

---

## Structure

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 567 commands
│   ├── agents/         ← 89 specialized agents (7 with decision trees: SPEC-147)
│   ├── skills/         ← 136 domain skills
│   ├── hooks/          ← 124 deterministic hooks
│   └── rules/          ← context and language rules
├── docs/               ← guides by role, scenario, sector
├── projects/           ← projects (git-ignored for privacy)
├── scripts/            ← validation, CI, utilities
├── zeroclaw/           ← ESP32 hardware + voice
└── CLAUDE.md           ← identity and core rules
```

---

## Documentation

| Section | Description |
|---|---|
| [Getting Started](docs/getting-started.md) | From zero to productive |
| [Data Flow](docs/data-flow-guide-es.md) | How the parts connect |
| [Confidentiality](docs/confidentiality-levels.md) | 5 levels (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Data sovereignty |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Commands & Agents](docs/readme/12-comandos-agentes.md) | Full reference |
| [Scenario Guides](docs/guides/README.md) | Azure, Jira, startup, healthcare... |
| [Adoption](docs/ADOPTION_GUIDE.md) | Step by step for consultancies |

---

## Principles

1. **Plain text is truth** — .md and .jsonl. Without AI, data remains readable
2. **Absolute privacy** — user data never leaves their machine
3. **The human decides** — AI proposes, never autonomous merge or deploy
4. **MIT** — no vendor lock-in, no telemetry

---

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). PRs welcome.

## License

[MIT](LICENSE) — Created by [la usuaria González Paz](https://github.com/gonzalezpazmonica)
