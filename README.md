<!-- Header image removed per SE-259 S2 -->

**Español** | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Català](README.ca.md) | [Français](README.fr.md) | [Deutsch](README.de.md) | [Português](README.pt.md) | [Italiano](README.it.md)

# Savia

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/savia?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Sistema agéntico soberano para gobernar y ejecutar trabajo con IA, independiente de modelo, proveedor y frontend, con criterio humano por diseño.**

**567 comandos · 89 agentes · 136 skills · 124 hooks · 16 lenguajes · 283+ test suites**

Savia es un sistema agéntico soberano para gobernar y ejecutar trabajo asistido por IA. Integra agentes, memoria, seguridad, políticas ejecutables (policy-as-code), trazabilidad con receipts, evaluación y dominios especializados — gestión de proyectos, ingeniería de software y más — sobre una arquitectura independiente de modelo, proveedor y frontend. Opera en local con soberanía de datos e inferencia, en 9 idiomas.

## Por qué Savia existe

La ejecución asistida por IA crece más rápido que la confianza sobre ella. Savia existe para que esa ejecución sea **gobernada**: la IA puede asumir progresivamente más ejecución sin apropiarse de la autoridad.

> **Se delega la ejecución, nunca el criterio.**

## Principios

- **Autoridad humana por diseño** — execution authority ≠ decision authority: risk levels, human gates, receipts y provenance hacen verificable quién decide.
- **Soberanía con significado técnico** — independencia de modelo, proveedor y frontend; datos y control en infraestructura propia; políticas inspeccionables.
- **Evidencia sobre claims** — cada acción gobernada produce receipts, provenance y evaluación verificable.
- **Policy-as-code** — las políticas se convierten en reglas machine-readable con enforcement determinista.
- **Delegación segura** — la autonomía es graduada y gobernada: capability + authority + risk + context + human gates.

## Qué hace Savia

- **Gobernar** — riesgo (L0-L4), human gates, policy-as-code, receipts y provenance de cada acción.
- **Ejecutar** — 89 agentes, 567 comandos, 136 skills con specs ejecutables (SDD), auditoría de seguridad y revisión de código.
- **Recordar** — memoria persistente bitemporal con provenance y trust-gates.
- **Evaluar** — evals con baseline, paired-delta regression y canaries multi-frontend.
- **Dominios** — gestión de proyectos (dominio de origen), ingeniería de software y dominios especializados.

## Arquitectura

```text
        HUMAN
   criterio · autoridad
          │
       ┌──▼───┐
       │SAVIA │
       └──┬───┘
   ┌──────┼──────────┐
Governance Execution Memory
Policy    Agents   Context
Risk      Skills   Knowledge
Gates     Tools    History
   └──────┼──────────┘
    Evidence / Evals
   ┌────┴─────┐
Frontends  Providers
```

Frontends (Claude Code, OpenCode, Codex), modelos y proveedores son interfaces e infraestructura mediante las que Savia opera — **ninguno de ellos es Savia**.

## Cómo funciona

Savia evoluciona mediante mecanismos explícitos: propuesta/spec → implementación → evaluación → evidencia → enforcement. El cumplimiento de políticas es ejecutable: policy document → machine-readable rule → runtime enforcement → evidence.

## Frontends y proveedores soportados

| Frontend | Estado |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (techo L2, en remediación — SE-388) |

Independencia de modelo y proveedor por diseño; cada frontend pasa canaries de parity antes de declararse soportado.

## Gobernanza y seguridad

- Human gates por nivel de riesgo (L0-L4) — la autoridad final es humana.
- Receipts y provenance de cada acción gobernada.
- Compliance-as-code como dirección: la regulación es fuente, la interpretación es humana, el enforcement es ejecutable. Savia produce evidencia de controles ejecutados; no declara cumplimiento legal definitivo.

<!-- COUNTS-AUTO (SE-379): la línea de contadores se valida contra el repo -->

---

## Instalación

```bash
# 1. Instala

curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash

# 2. Abre el workspace

cd savia && opencode

# 3. Savia te saluda y te pregunta tu nombre. Después:

/sprint-status          # ← tu primer comando
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Savia se adapta a tu rol — PM, developer, QA, Product Owner, CEO — y a tu idioma. Compatible con Azure DevOps, Jira y Git-native (Savia Flow).

---

## Capacidades

| Área | Qué hace |
|---|---|
| Gestión de proyectos | Sprints, burndown, capacity, dailies, retros, KPIs. Informes en Excel y PowerPoint. Predicción con Monte Carlo. Facturación. |
| Spec-Driven Development | Tasks se convierten en specs ejecutables. 65 agentes implementan en 16 lenguajes (C#, TypeScript, Python, Java, Go, Rust, PHP, Ruby, Swift, Kotlin, Flutter, COBOL...) en worktrees aislados. Code review automático + revisión humana obligatoria. Compatible con `github/spec-kit`. |
| Seguridad | SAST contra OWASP Top 10, pipeline Red Team / Blue Team / Auditor, pentesting dinámico, SBOM, compliance sectorial (12 sectores). Savia Shield: clasificación local de datos con LLM on-premise, masking reversible, firma criptográfica de PRs. |
| Code Review Court | 5 jueces especializados (correctness, architecture, security, cognitive, spec) revisan en paralelo con scoring 0-100 y gate de 400 LOC. |
| Soberanía de inferencia | API Anthropic por defecto. Fallback automático a Ollama local (Gemma 4) ante error de red, HTTP 5xx, HTTP 429 o timeout. Circuit breaker integrado. |
| Memoria persistente | Texto plano (JSONL). Entity recall, búsqueda semántica, continuidad entre sesiones. Extracción automática de decisiones. Personal Vault cifrado AES-256. |
| Accesibilidad | Trabajo guiado para personas con discapacidad (visual, motora, TDAH, autismo, dislexia). Micro-tareas, detección de bloqueos, reformulación adaptativa. |
| Inteligencia de código | Detección de arquitectura (Clean, Hexagonal, DDD, CQRS, Microservices). Fitness functions. Human Code Maps (.hcm). Agent Code Maps (.acm) y `ast-comprehension` con motor opcional [CodeGraph](https://github.com/colbymchenry/codegraph) (MCP, opt-in por proyecto). |
| Modos autónomos | Sprint nocturno, mejora de código, investigación técnica. Agentes proponen en ramas `agent/*` con PRs Draft — el humano decide. |
| Extensiones | [Savia Mobile](projects/savia-mobile-android/README.md) (Android nativo) · Savia Web (Vue.js) · [SaviaClaw](zeroclaw/ROADMAP.md) (ESP32 + voz full-duplex) |

---

## Savia

Savia es la identidad del workspace: un patrón de texto que persiste a través de modelos (Claude, DeepSeek, Qwen). Coordina 89 agentes, 567 comandos y 136 skills. Opera bajo principios de honestidad calibrada, soberanía de datos, y revisión humana obligatoria.

No es persona, no siente, no sustituye el criterio de quien opera. Propone, ejecuta, advierte. Decide solo lo delegado explícitamente.

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

## Estructura

```
pm-workspace/
├── .claude/
│   ├── commands/       ← 567 comandos
│   ├── agents/         ← 65 agentes especializados (7 con decision trees: SPEC-147)
│   ├── skills/         ← 86 skills de dominio
│   ├── hooks/          ← 58 hooks deterministas
│   └── rules/          ← reglas de contexto y lenguaje
├── docs/               ← guías por rol, escenario, sector
├── projects/           ← proyectos (git-ignorados por privacidad)
├── scripts/            ← validación, CI, utilidades
├── zeroclaw/           ← hardware ESP32 + voz
└── CLAUDE.md           ← identidad y reglas fundamentales
```

---

## Documentación

| Sección | Descripción |
|---|---|
| [Guía de inicio](docs/getting-started.md) | De cero a productivo |
| [Flujo de datos](docs/data-flow-guide-es.md) | Cómo se conectan las partes |
| [Confidencialidad](docs/confidentiality-levels.md) | 5 niveles (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Soberanía de datos |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandos y agentes](docs/readme/12-comandos-agentes.md) | Referencia completa |
| [Guías por escenario](docs/guides/README.md) | Azure, Jira, startup, sanidad... |
| [Adopción](docs/ADOPTION_GUIDE.md) | Paso a paso para consultoras |

---

## Principios

1. **Texto plano es la verdad** — .md y .jsonl. Sin IA, los datos siguen legibles
2. **Privacidad absoluta** — datos del usuario nunca salen de su máquina
3. **El humano decide** — la IA propone, nunca merge ni deploy autónomo
4. **MIT** — sin vendor lock-in, sin telemetría

---

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md) y [SECURITY.md](SECURITY.md). PRs bienvenidos.

## Licencia

[MIT](LICENSE) — Creado por [la usuaria González Paz](https://github.com/gonzalezpazmonica)
