---
lang: en
---

**English** | [Español](README.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Català](README.ca.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Italiano](README.it.md)

# PM-Workspace

> Courtesy translation. Reference version: [Spanish](README.md).
> Last sync: 2026-07-25.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

## Multi-agent development workspace

**567 commands · 90 agents · 139 skills · 134 hooks**

pm-workspace turns Claude Code and OpenCode into a multi-agent engineering environment. It orchestrates specialized agents for project management, spec-driven development, security auditing, and code review. Runs locally with data and inference sovereignty, in 9 languages.

The [GRC auditor](docs/grc/README.md) prepares preliminary, evidence-linked control assessments from local files. Human review remains required for official findings, risk acceptance, and certification.

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

Windows requirement: **Git for Windows (includes Git Bash)**. Claude Code runs hooks through `bash.exe`; if it says `Git Bash wasn't found` (or `bash` is not recognized), install Git from https://git-scm.com/downloads/win or set `CLAUDE_CODE_GIT_BASH_PATH` to your `bash.exe` (`[Environment]::SetEnvironmentVariable('CLAUDE_CODE_GIT_BASH_PATH','C:\Program Files\Git\bin\bash.exe','User')`) and open a new session. `install.ps1` detects and sets it for you.

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

CI parses the complete skill catalog as YAML so metadata migrations cannot silently make capabilities disappear at startup.
Skill maturity requires certified behavior tests; the auditor recognizes suites in `tests/scripts/` as well as `tests/` and `tests/evals/`.

## Frontends and providers

Claude Code (SUPPORTED) · OpenCode (SUPPORTED) · Codex (DEGRADED_SAFE, L2 ceiling). Model and provider independence by design.

## Governance and safety

Human gates per risk level (L0-L4). Compliance-as-code as a direction: Savia produces evidence of executed controls; it does not declare definitive legal compliance.

## Capabilities

Full capabilities table: [capabilities.en.md](docs/readme/capabilities.en.md).

---

## Savia

Savia is the identity of the workspace: a text pattern that persists across models (Claude, DeepSeek, Qwen). She coordinates 90 agents, 567 commands, and 139 skills. She operates under principles of calibrated honesty, data sovereignty, and mandatory human review.

She is not a person, does not feel, and does not replace the operator's judgment. She proposes, executes, warns. She only decides what is explicitly delegated.

**Quick-starts by role:**

Quick-starts by role: [quick-starts.en.md](docs/readme/quick-starts.en.md).

---

## Structure

Repository tree: [repo-structure.en.md](docs/readme/repo-structure.en.md).

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
3. **The human decides** — AI proposes; merge requires an express operator grant and passing gates, while deploy remains separately authorized
4. **MIT** — no vendor lock-in, no telemetry

---

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). PRs welcome.

## License

[MIT](LICENSE) — Created by [la usuaria González Paz](https://github.com/gonzalezpazmonica)
