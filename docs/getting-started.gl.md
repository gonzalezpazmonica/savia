# Guia de Inicio — pm-workspace

> De cero a produtivo en 15 minutos.

---

## 1. Prerequisitos

- **Claude Code / OpenCode** instalado e autenticado (`claude --version` ou `opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 para PRs e issues (`gh --version`)
- **jq** para parseo JSON (`jq --version`)
- (Opcional) **Ollama** para Savia Shield (`ollama --version`)

## 2. Clonar e primeiro arranque

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

Ao arrancar, Savia detecta que non tes perfil e preséntase. Responde as súas preguntas: nome, rol, proxectos. Isto crea o teu perfil en `.claude/profiles/users/{slug}/`.

Se queres saltar o perfil: escribe directamente un comando. Savia non insiste.

## 3. Configurar o teu proxecto

```bash
/project-new
```

Segue o wizard. Savia detecta a túa ferramenta PM (Azure DevOps, Jira, ou Savia Flow) e crea a estrutura en `projects/{nome}/`.

Para Azure DevOps, necesitas un PAT gardado en `$HOME/.azure/devops-pat` (unha liña, sen salto). Scopes: Work Items R/W, Project R, Analytics R.

## 4. Perfís de hooks (Savia Shield)

Os hooks controlan que regras se executan automaticamente. Hai 4 perfís:

| Perfil | Que activa | Cando usalo |
|--------|-----------|-------------|
| `minimal` | Só seguridade básica | Demos, primeiros pasos |
| `standard` | Seguridade + calidade | Traballo diario (por defecto) |
| `strict` | Seguridade + calidade + escrutinio extra | Pre-release, código crítico |
| `ci` | Igual que standard, non interactivo | Pipelines CI/CD |

```bash
# Ver perfil activo
bash scripts/hook-profile.sh get

# Cambiar perfil
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (protección de datos)

Se traballas con datos de clientes, activa Savia Shield:

```bash
/savia-shield enable
/savia-shield status
```

Shield protexe datos sensíbeis (N4/N4b) de filtrarse a ficheiros públicos (N1). Funciona con 5 capas: regex, LLM local, auditoría post-escritura, masking reversíbel e detección base64.

Guía completa: [docs/savia-shield-guide.gl.md](savia-shield-guide.gl.md)

## 6. Mapas: .scm e .ctx

pm-workspace xera dous índices navegábeis:

- **`.scm` (Capability Map)**: catálogo de comandos, skills e axentes indexados por intención. Responde a "que pode facer Savia".
- **`.ctx` (Context Index)**: mapa de onde vive cada tipo de información (regras, memoria, proxectos). Responde a "onde buscar ou gardar datos".

Ambos son texto plano, auto-xerados, con carga progresiva (L0/L1/L2).

Estado: en proposta (SPEC-053, SPEC-054). Cando estean dispoñíbeis, xéranse con:

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Quickstart por rol

| Rol | Primeiros comandos | Rutina diaria |
|-----|-------------------|---------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PRs, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Cada rol ten unha guía detallada: `docs/quick-starts/quick-start-{rol}.md`

## 8. Referencia de configuración

| Que configurar | Onde | Exemplo |
|----------------|------|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Token dunha liña |
| Perfil de usuario | `.claude/profiles/users/{slug}/` | Creado por `/profile-setup` |
| Hook profile | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Conectores | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Proxecto PM tool | `projects/{nome}/CLAUDE.md` | Org URL, iteration path |
| Config privada | `CLAUDE.local.md` (gitignored) | Proxectos reais |

## 9. Rendemento

- **CLAUDE.md consume tokens en cada quenda** (non se cachea) — manteno escueto e por baixo de 150 linas
- **Os skills non consomen contexto ata que se invocan** — ter moitos skills e de balde
- **auto-compact disparase ao 65%** da ventana de contexto — executa `/compact` manualmente se notas degradacion antes
- **As entradas de memoria deben ser < 150 caracteres** — resumos curtos carganse mais rapido e ocupan menos contexto
- Detalle completo: `docs/best-practices-claude-code.md`

## 10. Seguintes pasos

1. Executa `/help` para ver o catálogo interactivo de comandos
2. Executa `/daily-routine` para que Savia che propoña a túa rutina
3. Le a guía do teu rol en `docs/quick-starts/`
4. Se usas datos de clientes: activa Savia Shield
5. Se algo falla: `/workspace-doctor` diagnostica o contorno

---

> Documentación detallada: `docs/readme/` (13 seccións) e `docs/guides/` (15 guías por escenario).
