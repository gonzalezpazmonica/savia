---
lang: en
---

**English** | [Español](README.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Català](README.ca.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Italiano](README.it.md)

# Savia

> Courtesy translation. Reference version: [Spanish](README.md).
> Last sync: 2026-10-30.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/savia?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia is an agentic R&D&I meta-orchestrator: she coordinates specialised agents and harnesses, research lines, governed knowledge domes and projects, with authority always resting with the person. Open source and sovereign.**

**567 commands · 90 agents · 139 skills · 134 hooks**

Savia orchestrates AI-assisted R&D&I work: she distributes tasks among specialised harnesses (executors, independent reviewers, external providers), sustains research lines, governs knowledge in domes (Savia Vaults) and manages projects as one more capability. She integrates memory, security, executable policies (policy-as-code), traceability with receipts and evaluation on an architecture independent of model, provider and frontend. She runs locally with data and inference sovereignty, in 9 languages.

## Why Savia exists

AI-assisted execution is growing faster than trust in it. Savia exists so that this execution is **governed**: AI can progressively take on more execution without taking over authority.

> **Execution is delegated, judgement never is.**

## Principles

- **Human authority by design** — execution authority ≠ decision authority: risk levels, human gates, receipts and provenance make who decides verifiable.
- **Sovereignty with technical meaning** — independence from model, provider and frontend; data and control on your own infrastructure; inspectable policies.
- **Evidence over claims** — every governed action produces receipts, provenance and verifiable evaluation.
- **Policy-as-code** — policies become machine-readable rules with deterministic enforcement.
- **Safe delegation** — autonomy is graduated and governed: capability + authority + risk + context + human gates.

## What Savia does

- **Orchestrate** — meta-orchestration of specialised harnesses: a contract-driven executor, independent reviewers and external providers, with deterministic invocation and authority resting with the person.
- **Research** — research lines with hypotheses, experiments and verifiable lessons.
- **Govern** — risk (L0-L4), human gates, policy-as-code, receipts and provenance for every action.
- **Execute** — 90 agents, 567 commands, 139 skills with executable specs (SDD), security audits and code review.
- **Know** — governed knowledge domes (Savia Vaults) and bitemporal persistent memory with provenance and trust gates.
- **Evaluate** — evals with baseline, paired-delta regression and multi-frontend canaries.
- **Domains** — project management (sprints, backlog, reports; one more capability), software engineering and specialised domains.
- **Preliminary GRC** — the [GRC auditor](docs/grc/README.md) links requirements, controls and local evidence to traceable findings. Decisions and certifications require human review.

## Architecture

Full diagram (Spanish): [architecture.es.md](docs/readme/architecture.es.md).

Frontends (Claude Code, OpenCode, Codex), models and providers are interfaces and infrastructure through which Savia operates — **none of them is Savia**.

## How it works

Savia evolves through explicit mechanisms: proposal/spec → implementation → evaluation → evidence → enforcement. Policy compliance is executable: policy document → machine-readable rule → runtime enforcement → evidence.

The skill catalogue is validated as complete YAML in CI so that a metadata migration cannot leave capabilities invisible at startup.
The maturity of each skill requires certified behavioural tests; the auditor recognises the suites in `tests/scripts/` as well as those in `tests/` and `tests/evals/`.

## Supported frontends and providers

| Frontend | Status |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (L2 ceiling, under remediation — SE-388) |

Model and provider independence by design; each frontend passes parity canaries before being declared supported.

## Governance and security

- Human gates per risk level (L0-L4) — final authority is human.
- Receipts and provenance for every governed action.
- Compliance-as-code as a direction: regulation is the source, interpretation is human, enforcement is executable. Savia produces evidence of executed controls; she does not declare definitive legal compliance.

---

## Installation

```bash
# 1. Install
curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash
# 2. Open the workspace
cd savia && opencode
# 3. Savia greets you and asks your name. Then:
/help                   # ← your first command: the capability map
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia adapts to your role — research, development, technical leadership, project management, QA, product — and to your language. For projects, compatible with Azure DevOps, Jira and Git-native (Savia Flow).

---

## Capabilities

Full capability table: [capabilities.en.md](docs/readme/capabilities.en.md).

---

## Savia

Savia is the identity of the workspace: a text pattern that persists across models (Claude, DeepSeek, Qwen). As a meta-orchestrator, she coordinates 90 agents, 567 commands, 139 skills and external harnesses. She operates under principles of calibrated honesty, data sovereignty and mandatory human review.

She is not a person, does not feel, and does not replace the judgement of whoever operates her. She proposes, executes, warns. She decides only what has been explicitly delegated.

Quick-starts by role: [quick-starts.en.md](docs/readme/quick-starts.en.md).

---

## Structure

Repository tree: [repo-structure.en.md](docs/readme/repo-structure.en.md).

---

## Documentation

| Section | Description |
|---|---|
| [Getting started](docs/getting-started.en.md) | From zero to productive |
| [Data flow](docs/data-flow-guide-en.md) | How the parts connect |
| [Confidentiality](docs/confidentiality-levels.md) | 5 levels (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Data sovereignty |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Commands and agents](docs/readme/12-comandos-agentes.md) | Full reference |
| [Scenario guides](docs/guides_en/README.md) | Azure, Jira, startup, healthcare... |
| [Adoption](docs/ADOPTION_GUIDE.en.md) | Step by step for consultancies |

---

## Foundations

1. **Plain text is the truth** — .md and .jsonl. Without AI, the data stays readable
2. **Absolute privacy** — user data never leaves their machine
3. **The human decides** — AI proposes; merge requires an explicit grant and green gates, deploy requires separate authorisation
4. **MIT** — no vendor lock-in, no telemetry

---

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). PRs welcome.

## License

[MIT](LICENSE) — Created by [la usuaria González Paz](https://github.com/gonzalezpazmonica)
