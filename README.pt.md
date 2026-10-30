---
lang: pt
---

**Portugues** | [Espanhol](README.md) | [English](README.en.md) | [Galego](README.gl.md) | [Euskara](README.eu.md) | [Catala](README.ca.md) | [Francais](README.fr.md) | [Deutsch](README.de.md) | [Italiano](README.it.md)

# Savia

> Tradução de cortesia. Versão de referência: [espanhol](README.md).
> Última sincronização: 2026-10-30.

[![CI](https://img.shields.io/github/actions/workflow/status/gonzalezpazmonica/savia/ci.yml?branch=main&label=CI&logo=github)](https://github.com/gonzalezpazmonica/savia/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/gonzalezpazmonica/pm-workspace?logo=github)](https://github.com/gonzalezpazmonica/savia/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](CONTRIBUTING.md)

**Savia é uma metaorquestradora agêntica de I&D&I: coordena agentes e harnesses especializados, linhas de investigação, cúpulas de conhecimento governado e projetos, com a autoridade sempre na pessoa. Open source e soberana.**

**567 comandos · 90 agentes · 139 skills · 134 hooks**

Savia orquestra o trabalho de I&D&I com IA: distribui tarefas entre harnesses especializados (executores, revisoras independentes, fornecedores externos), sustenta linhas de investigação, governa o conhecimento em cúpulas (Savia Vaults) e gere projetos como mais uma capacidade. Integra memória, segurança, políticas executáveis (policy-as-code), rastreabilidade com receipts e avaliação sobre uma arquitetura independente de modelo, fornecedor e frontend. Opera em local com soberania de dados e de inferência, em 9 idiomas.

## Porque existe Savia

A execução assistida por IA cresce mais depressa do que a confiança nela. Savia existe para que essa execução seja **governada**: a IA pode assumir progressivamente mais execução sem se apropriar da autoridade.

> **Delega-se a execução, nunca o critério.**

## Princípios

- **Autoridade humana por design** — execution authority ≠ decision authority: níveis de risco, human gates, receipts e provenance tornam verificável quem decide.
- **Soberania com significado técnico** — independência de modelo, fornecedor e frontend; dados e controlo em infraestrutura própria; políticas inspecionáveis.
- **Evidência acima de claims** — cada ação governada produz receipts, provenance e avaliação verificável.
- **Policy-as-code** — as políticas tornam-se regras machine-readable com enforcement determinista.
- **Delegação segura** — a autonomia é graduada e governada: capability + authority + risk + context + human gates.

## O que faz Savia

- **Orquestrar** — metaorquestração de harnesses especializados: um executor por contrato, revisoras independentes e fornecedores externos, com invocação determinista e a autoridade na pessoa.
- **Investigar** — linhas de investigação com hipóteses, experiências e lições verificáveis.
- **Governar** — risco (L0-L4), human gates, policy-as-code, receipts e provenance de cada ação.
- **Executar** — 90 agentes, 567 comandos, 139 skills com specs executáveis (SDD), auditoria de segurança e revisão de código.
- **Conhecer** — cúpulas de conhecimento governado (Savia Vaults) e memória persistente bitemporal com provenance e trust-gates.
- **Avaliar** — evals com baseline, paired-delta regression e canaries multi-frontend.
- **Domínios** — gestão de projetos (sprints, backlog, relatórios; mais uma capacidade), engenharia de software e domínios especializados.
- **GRC preliminar** — o [auditor GRC](docs/grc/README.md) liga requisitos, controlos e provas locais a constatações rastreáveis. As decisões e certificações requerem revisão humana.

## Arquitetura

Diagrama completo (em espanhol): [architecture.es.md](docs/readme/architecture.es.md).

Os frontends (Claude Code, OpenCode, Codex), os modelos e os fornecedores são interfaces e infraestrutura através das quais Savia opera — **nenhum deles é Savia**.

## Como funciona

Savia evolui através de mecanismos explícitos: proposta/spec → implementação → avaliação → evidência → enforcement. O cumprimento de políticas é executável: policy document → machine-readable rule → runtime enforcement → evidence.

O catálogo de skills é validado como YAML completo em CI para impedir que uma migração de metadados deixe capacidades invisíveis no arranque.
A maturidade de cada skill exige testes de comportamento certificados; o auditor reconhece as suites de `tests/scripts/` além das de `tests/` e `tests/evals/`.

## Frontends e fornecedores suportados

| Frontend | Estado |
|---|---|
| Claude Code | SUPPORTED |
| OpenCode | SUPPORTED |
| Codex | DEGRADED_SAFE (teto L2, em remediação — SE-388) |

Independência de modelo e fornecedor por design; cada frontend passa canaries de paridade antes de ser declarado suportado.

## Governança e segurança

- Human gates por nível de risco (L0-L4) — a autoridade final é humana.
- Receipts e provenance de cada ação governada.
- Compliance-as-code como direção: a regulação é a fonte, a interpretação é humana, o enforcement é executável. Savia produz evidência de controlos executados; não declara cumprimento legal definitivo.

---

## Instalação

```bash
# 1. Instala
curl -fsSL https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.sh | bash
# 2. Abre o workspace
cd savia && opencode
# 3. Savia cumprimenta-te e pergunta o teu nome. Depois:
/help                   # ← o teu primeiro comando: o mapa de capacidades
```

**Windows:** `irm https://raw.githubusercontent.com/gonzalezpazmonica/savia/main/install.ps1 | iex`

Requisito no Windows: **Git for Windows (inclui Git Bash)**. Se o Claude Code disser `Git Bash wasn't found`, instale o Git (https://git-scm.com/downloads/win) ou defina `CLAUDE_CODE_GIT_BASH_PATH` com o caminho do seu `bash.exe` e abra uma sessão nova.

Savia adapta-se ao teu papel — investigação, desenvolvimento, direção técnica, gestão de projetos, QA, produto — e ao teu idioma. Para projetos, compatível com Azure DevOps, Jira e Git-native (Savia Flow).

---

## Capacidades

Tabela completa de capacidades: [capabilities.pt.md](docs/readme/capabilities.pt.md).

---

## Savia

Savia é a identidade do workspace: um padrão de texto que persiste através de modelos (Claude, DeepSeek, Qwen). Como metaorquestradora, coordena 90 agentes, 567 comandos, 139 skills e harnesses externos. Opera sob princípios de honestidade calibrada, soberania de dados e revisão humana obrigatória.

Não é uma pessoa, não sente, não substitui o critério de quem a opera. Propõe, executa, alerta. Decide apenas o que lhe foi delegado explicitamente.

Quick-starts por papel: [quick-starts.pt.md](docs/readme/quick-starts.pt.md).

---

## Estrutura

Árvore do repositório: [repo-structure.pt.md](docs/readme/repo-structure.pt.md).

---

## Documentação

| Secção | Descrição |
|---|---|
| [Guia de início](docs/getting-started.pt.md) | Do zero a produtivo |
| [Fluxo de dados](docs/data-flow-guide-es.md) | Como as partes se ligam (em espanhol) |
| [Confidencialidade](docs/confidentiality-levels.md) | 5 níveis (N1-N4b) |
| [Savia Shield](docs/savia-shield.md) | Soberania de dados |
| [SDD](docs/readme/05-sdd.md) | Spec-Driven Development |
| [Comandos e agentes](docs/readme/12-comandos-agentes.md) | Referência completa |
| [Guias por cenário](docs/guides/README.md) | Azure, Jira, startup, saúde... |
| [Adoção](docs/ADOPTION_GUIDE.md) | Passo a passo para consultoras |

---

## Fundamentos

1. **O texto simples é a verdade** — .md e .jsonl. Sem IA, os dados continuam legíveis
2. **Privacidade absoluta** — os dados do utilizador nunca saem da sua máquina
3. **O humano decide** — a IA propõe; o merge exige um grant expresso e gates verdes, o deploy requer autorização separada
4. **MIT** — sem vendor lock-in, sem telemetria

---

## Contribuir

Lê [CONTRIBUTING.md](CONTRIBUTING.md) e [SECURITY.md](SECURITY.md). PRs bem-vindos.

## Licença

[MIT](LICENSE) — Criado por [la usuaria Gonzalez Paz](https://github.com/gonzalezpazmonica)
