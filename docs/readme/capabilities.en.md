# Capabilities

| Area | What it does |
|---|---|
| Project management | Sprints, burndown, capacity, dailies, retros, KPIs. Excel and PowerPoint reports. Monte Carlo forecasting. Billing. |
| Spec-Driven Development | Tasks become executable specs. 90 agents implement in 16 languages (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) in isolated worktrees. Automated code review + human review, including review by a sole operator. Compatible with `github/spec-kit`. |
| Security | SAST against OWASP Top 10, Red Team / Blue Team / Auditor pipeline, dynamic pentesting, SBOM, sector compliance (12 sectors). Savia Shield: local data classification with on-premise LLM, reversible masking, cryptographic PR signing. |
| Code Review Court | 5 specialized judges (correctness, architecture, security, cognitive, spec) review in parallel with 0-100 scoring and a 400 LOC gate. |
| Inference sovereignty | Anthropic API by default. Automatic fallback to local Ollama (Gemma 4) on network error, HTTP 5xx, HTTP 429, or timeout. Integrated circuit breaker. |
| Persistent memory | Plain text (JSONL). Entity recall, semantic search, cross-session continuity. Automatic decision extraction. AES-256 encrypted Personal Vault. |
| Accessibility | Guided work for people with disabilities (visual, motor, ADHD, autism, dyslexia). Micro-tasks, block detection, adaptive reformulation. |
| Code intelligence | Architecture detection (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) and `ast-comprehension` with optional [CodeGraph](https://github.com/colbymchenry/codegraph) engine (MCP, opt-in per project). |
| Autonomous modes | Overnight sprint, code improvement, tech research. Agents propose on `agent/*` branches with Draft PRs; a sole operator can review and merge with an express grant and passing gates. |
| Extensions | [Savia Mobile](../../projects/savia-mobile-android/README.md) (native Android) · Savia Web (Vue.js) · [SaviaClaw](../../zeroclaw/ROADMAP.md) (ESP32 + full-duplex voice) |

---

Back to the [README](../../README.en.md).
