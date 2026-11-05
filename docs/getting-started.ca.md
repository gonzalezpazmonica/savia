# Guia d'Inici — pm-workspace

> De zero a productiu en 15 minuts.

---

## 1. Prerequisits

- **Claude Code / OpenCode** instal·lat i autenticat (`claude --version` o `opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 per a PRs i issues (`gh --version`)
- **jq** per a parseig JSON (`jq --version`)
- (Opcional) **Ollama** per a Savia Shield (`ollama --version`)

## 2. Clonar i primer arrencada

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

En arrencar, Savia detecta que no tens perfil i es presenta. Respon a les seves preguntes: nom, rol, projectes. Aixo crea el teu perfil a `.claude/profiles/users/{slug}/`.

Si vols saltar el perfil: escriu directament una comanda. Savia no insisteix.

## 3. Configurar el teu projecte

```bash
/project-new
```

Segueix el wizard. Savia detecta la teva eina PM (Azure DevOps, Jira, o Savia Flow) i crea l'estructura a `projects/{nom}/`.

Per a Azure DevOps, necessites un PAT guardat a `$HOME/.azure/devops-pat` (una linia, sense salt). Scopes: Work Items R/W, Project R, Analytics R.

## 4. Perfils de hooks (Savia Shield)

Els hooks controlen quines regles s'executen automaticament. Hi ha 4 perfils:

| Perfil | Que activa | Quan fer-lo servir |
|--------|-----------|-------------------|
| `minimal` | Nomes seguretat basica | Demos, primers passos |
| `standard` | Seguretat + qualitat | Treball diari (default) |
| `strict` | Seguretat + qualitat + escrutini extra | Pre-release, codi critic |
| `ci` | Igual que standard, no interactiu | Pipelines CI/CD |

```bash
# Veure perfil actiu
bash scripts/hook-profile.sh get

# Canviar perfil
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (proteccio de dades)

Si treballes amb dades de clients, activa Savia Shield:

```bash
/savia-shield enable
/savia-shield status
```

Shield protegeix dades sensibles (N4/N4b) de filtrar-se a fitxers publics (N1). Funciona amb 5 capes: regex, LLM local, auditoria post-escriptura, masking reversible i deteccio base64.

Guia completa: [docs/savia-shield-guide.ca.md](savia-shield-guide.ca.md)

## 6. Mapes: .scm i .ctx

pm-workspace genera dos indexos navegables:

- **`.scm` (Capability Map)**: cataleg de comandes, skills i agents indexats per intencio. Respon a "que pot fer Savia".
- **`.ctx` (Context Index)**: mapa de on viu cada tipus d'informacio (regles, memoria, projectes). Respon a "on buscar o guardar dades".

Ambdos son text pla, auto-generats, amb carrega progressiva (L0/L1/L2).

Estat: en proposta (SPEC-053, SPEC-054). Quan estiguin disponibles, es generen amb:

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Quickstart per rol

| Rol | Primeres comandes | Rutina diaria |
|-----|-------------------|---------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PRs, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Cada rol te una guia detallada: `docs/quick-starts/quick-start-{rol}.md`

## 8. Referencia de configuracio

| Que configurar | On | Exemple |
|----------------|-----|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Token d'una linia |
| Perfil d'usuari | `.claude/profiles/users/{slug}/` | Creat per `/profile-setup` |
| Hook profile | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Connectors | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Projecte PM tool | `projects/{nom}/CLAUDE.md` | Org URL, iteration path |
| Config privada | `CLAUDE.local.md` (gitignored) | Projectes reals |

## 9. Rendiment

- **CLAUDE.md consumeix tokens a cada torn** (no es cacheja) — mantin-lo breu i per sota de 150 linies
- **Els skills no consumeixen contexte fins que s'invoquen** — tenir molts skills es gratuit
- **auto-compact s'activa al 65%** de la finestra de contexte — executa `/compact` manualment si notes degradacio abans
- **Les entrades de memoria han de ser < 150 caracters** — resums curts es carreguen mes rapid i ocupen menys contexte
- Detall complet: `docs/best-practices-claude-code.md`

## 10. Seguents passos

1. Executa `/help` per veure el cataleg interactiu de comandes
2. Executa `/daily-routine` perque Savia et proposi la teva rutina
3. Llegeix la guia del teu rol a `docs/quick-starts/`
4. Si uses dades de clients: activa Savia Shield
5. Si alguna cosa falla: `/workspace-doctor` diagnostica l'entorn

---

> Documentacio detallada: `docs/readme/` (13 seccions) i `docs/guides/` (15 guies per escenari).
