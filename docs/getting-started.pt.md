# Guia de Inicio — pm-workspace

> De zero a produtivo em 15 minutos.

---

## 1. Pre-requisitos

- **Claude Code / OpenCode** instalado e autenticado (`claude --version` ou `opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 para PRs e issues (`gh --version`)
- **jq** para parsing JSON (`jq --version`)
- (Opcional) **Ollama** para Savia Shield (`ollama --version`)

## 2. Clonar e primeiro arranque

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

Ao iniciar, Savia detecta que nao existe perfil e se apresenta. Responda as perguntas: nome, papel, projetos. Isso cria seu perfil em `.claude/profiles/users/{slug}/`.

Se quiser pular o perfil: digite diretamente um comando. Savia nao insiste.

## 3. Configurar seu projeto

```bash
/project-new
```

Siga o wizard. Savia detecta sua ferramenta PM (Azure DevOps, Jira ou Savia Flow) e cria a estrutura em `projects/{nome}/`.

Para Azure DevOps, voce precisa de um PAT salvo em `$HOME/.azure/devops-pat` (uma linha, sem quebra). Scopes: Work Items R/W, Project R, Analytics R.

## 4. Perfis de hooks (Savia Shield)

Os hooks controlam quais regras sao executadas automaticamente. Existem 4 perfis:

| Perfil | O que ativa | Quando usar |
|--------|------------|-------------|
| `minimal` | Apenas seguranca basica | Demos, primeiros passos |
| `standard` | Seguranca + qualidade | Trabalho diario (padrao) |
| `strict` | Seguranca + qualidade + escrutinio extra | Pre-release, codigo critico |
| `ci` | Igual ao standard, nao interativo | Pipelines CI/CD |

```bash
# Ver perfil ativo
bash scripts/hook-profile.sh get

# Mudar perfil
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (protecao de dados)

Se voce trabalha com dados de clientes, ative Savia Shield:

```bash
/savia-shield enable
/savia-shield status
```

Shield protege dados sensiveis (N4/N4b) contra vazamento para arquivos publicos (N1). Funciona com 5 camadas: regex, LLM local, auditoria pos-escrita, mascaramento reversivel e detecao base64.

Guia completo: [docs/savia-shield-guide.pt.md](savia-shield-guide.pt.md)

## 6. Mapas: .scm e .ctx

pm-workspace gera dois indices navegaveis:

- **`.scm` (Capability Map)**: catalogo de comandos, skills e agentes indexados por intencao. Responde a "o que Savia pode fazer".
- **`.ctx` (Context Index)**: mapa de onde cada tipo de informacao reside (regras, memoria, projetos). Responde a "onde buscar ou guardar dados".

Ambos sao texto puro, auto-gerados, com carregamento progressivo (L0/L1/L2).

Status: em proposta (SPEC-053, SPEC-054). Quando disponiveis, sao gerados com:

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Quickstart por papel

| Papel | Primeiros comandos | Rotina diaria |
|-------|-------------------|---------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PRs, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Cada papel tem um guia detalhado: `docs/quick-starts/quick-start-{papel}.md`

## 8. Referencia de configuracao

| O que configurar | Onde | Exemplo |
|------------------|------|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Token de uma linha |
| Perfil de usuario | `.claude/profiles/users/{slug}/` | Criado por `/profile-setup` |
| Perfil de hook | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Conectores | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Projeto ferramenta PM | `projects/{nome}/CLAUDE.md` | Org URL, iteration path |
| Config privada | `CLAUDE.local.md` (gitignored) | Projetos reais |

## 9. Desempenho

- **CLAUDE.md consome tokens a cada turno** (nao e cacheado) — mantenha enxuto e abaixo de 150 linhas
- **Skills nao consomem contexto ate serem invocados** — ter muitos skills e gratuito
- **auto-compact dispara aos 65%** da janela de contexto — execute `/compact` manualmente se notar degradacao antes
- **Entradas de memoria devem ter < 150 caracteres** — resumos curtos carregam mais rapido e ocupam menos contexto
- Detalhes completos: `docs/best-practices-claude-code.md`

## 10. Proximos passos

1. Execute `/help` para ver o catalogo interativo de comandos
2. Execute `/daily-routine` para Savia propor sua rotina
3. Leia o guia do seu papel em `docs/quick-starts/`
4. Se trabalha com dados de clientes: ative Savia Shield
5. Se algo falhar: `/workspace-doctor` diagnostica o ambiente

---

> Documentacao detalhada: `docs/readme/` (13 secoes) e `docs/guides/` (15 guias por cenario).
