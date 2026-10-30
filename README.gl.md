---
lang: gl
---

**Galego** | [Castelan](README.md) | [English](README.en.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Portugues](README.pt.md) | [Italiano](README.it.md)

# Savia

> Tradución de cortesía. Versión de referencia: [español](README.md).
> Última sincronización: 2026-10-30.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia é unha metaorquestradora axéntica de I+D+i: coordina axentes e harnesses especializados, liñas de investigación, cúpulas de coñecemento gobernado e proxectos, coa autoridade sempre na persoa. Open source e soberana.**

**567 comandos · 90 axentes · 139 skills · 134 hooks**

Savia orquestra o traballo de I+D+i con IA: reparte tarefas entre harnesses especializados (executores, revisoras independentes, provedores externos), sostén liñas de investigación, goberna o coñecemento en cúpulas (Savia Vaults) e xestiona proxectos como unha capacidade máis. Integra memoria, seguridade, políticas executables (policy-as-code), trazabilidade con receipts e avaliación sobre unha arquitectura independente de modelo, provedor e frontend. Opera en local con soberanía de datos e de inferencia, en 9 idiomas.

## Por que existe Savia

A execución asistida por IA crece máis rápido ca a confianza nela. Savia existe para que esa execución sexa **gobernada**: a IA pode asumir progresivamente máis execución sen apropiarse da autoridade.

> **Delégase a execución, nunca o criterio.**

## Principios

- **Autoridade humana por deseño** — execution authority ≠ decision authority: niveis de risco, human gates, receipts e provenance fan verificable quen decide.
- **Soberanía con significado técnico** — independencia de modelo, provedor e frontend; datos e control en infraestrutura propia; políticas inspeccionables.
- **Evidencia sobre claims** — cada acción gobernada produce receipts, provenance e avaliación verificable.
- **Policy-as-code** — as políticas convértense en regras machine-readable con enforcement determinista.
- **Delegación segura** — a autonomía é graduada e gobernada: capability + authority + risk + context + human gates.

## Que fai Savia

- **Orquestrar** — metaorquestración de harnesses especializados: un executor por contrato, revisoras independentes e provedores externos, con invocación determinista e a autoridade na persoa.
- **Investigar** — liñas de investigación con hipóteses, experimentos e leccións verificables.
- **Gobernar** — risco (L0-L4), human gates, policy-as-code, receipts e provenance de cada acción.
- **Executar** — 90 axentes, 567 comandos, 139 skills con specs executables (SDD), auditoría de seguridade e revisión de código.
- **Coñecer** — cúpulas de coñecemento gobernado (Savia Vaults) e memoria persistente bitemporal con provenance e trust-gates.
- **Avaliar** — evals con baseline, paired-delta regression e canaries multi-frontend.
- **Dominios** — xestión de proxectos (sprints, backlog, informes; unha capacidade máis), enxeñaría de software e dominios especializados.
- **GRC preliminar** — o [auditor GRC](docs/grc/README.md) liga requisitos, controis e probas locais con achados trazables. As decisións e certificacións requiren revisión humana.

## Arquitectura

Diagrama completo (en español): [architecture.es.md](docs/readme/architecture.es.md).

Os frontends (Claude Code, OpenCode, Codex), os modelos e os provedores son interfaces e infraestrutura mediante as que opera Savia — **ningún deles é Savia**.

## Como funciona

Savia evoluciona mediante mecanismos explícitos: proposta/spec → implementación → avaliación → evidencia → enforcement. O cumprimento de políticas é executable: policy document → machine-readable rule → runtime enforcement → evidence.

O catálogo de skills valídase como YAML completo en CI para impedir que unha migración de metadatos deixe capacidades invisibles ao arrincar.
A madurez de cada skill esixe probas de comportamento certificadas; o auditor recoñece as suites de `tests/scripts/` ademais das de `tests/` e `tests/evals/`.

## Frontends e provedores soportados

| Frontend | Estado |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (teito L2, en remediación — SE-388) |

Independencia de modelo e provedor por deseño; cada frontend pasa canaries de paridade antes de declararse soportado.

## Gobernanza e seguridade

- Human gates por nivel de risco (L0-L4) — a autoridade final é humana.
- Receipts e provenance de cada acción gobernada.
- Compliance-as-code como dirección: a regulación é a fonte, a interpretación é humana, o enforcement é executable. Savia produce evidencia de controis executados; non declara cumprimento legal definitivo.

---

## Instalación

```bash
# 1. Instala
curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash
# 2. Abre o workspace
cd savia && opencode
# 3. Savia saúdate e pregúntache o nome. Despois:
/help                   # ← o teu primeiro comando: o mapa de capacidades
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Requisito en Windows: **Git for Windows (inclúe Git Bash)**. Se Claude Code di `Git Bash wasn't found`, instala Git (https://git-scm.com/downloads/win) ou fixa `CLAUDE_CODE_GIT_BASH_PATH` coa ruta do teu `bash.exe` e abre unha sesión nova.

Savia adáptase ao teu rol — investigación, desenvolvemento, dirección técnica, xestión de proxectos, QA, produto — e ao teu idioma. Para proxectos, compatible con Azure DevOps, Jira e Git-native (Savia Flow).

---

## Capacidades

Táboa completa de capacidades: [capabilities.gl.md](docs/readme/capabilities.gl.md).

---

## Savia

Savia é a identidade do workspace: un padrón de texto que persiste a través de modelos (Claude, DeepSeek, Qwen). Como metaorquestradora, coordina 90 axentes, 567 comandos, 139 skills e harnesses externos. Opera baixo principios de honestidade calibrada, soberanía de datos e revisión humana obrigatoria.

Non é unha persoa, non sente, non substitúe o criterio de quen a opera. Propón, executa, advirte. Decide só o que se lle delegou explicitamente.

Quick-starts por rol: [quick-starts.gl.md](docs/readme/quick-starts.gl.md).

---

## Estrutura

Árbore do repositorio: [repo-structure.gl.md](docs/readme/repo-structure.gl.md).

---

## Documentación

| Sección | Descrición |
|---|---|
| [Guía de inicio](docs/getting-started.gl.md) | De cero a produtivo |
| [Fluxo de datos](docs/data-flow-guide-es.md) | Como se conectan as partes (en español) |
| [Confidencialidade](docs/confidentiality-levels.md) | 5 niveis (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Soberanía de datos |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandos e axentes](docs/readme/12-comandos-agentes.md) | Referencia completa |
| [Guías por escenario](docs/guides/README.md) | Azure, Jira, startup, sanidade... |
| [Adopción](docs/ADOPTION_GUIDE.md) | Paso a paso para consultoras |

---

## Fundamentos

1. **O texto plano é a verdade** — .md e .jsonl. Sen IA, os datos seguen sendo lexibles
2. **Privacidade absoluta** — os datos do usuario nunca saen da súa máquina
3. **O humano decide** — a IA propón; o merge esixe un grant expreso e gates en verde, o deploy require autorización separada
4. **MIT** — sen vendor lock-in, sen telemetría

---

## Contribuír

Le [CONTRIBUTING.md](CONTRIBUTING.md) e [SECURITY.md](SECURITY.md). PRs benvidos.

## Licenza

[MIT](LICENSE) — Creado por [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
