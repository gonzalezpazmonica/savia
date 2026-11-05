# Guide de Demarrage — pm-workspace

> De zero a productif en 15 minutes.

---

## 1. Prerequis

- **Claude Code / OpenCode** installe et authentifie (`claude --version` ou `opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 pour les PRs et issues (`gh --version`)
- **jq** pour le parsing JSON (`jq --version`)
- (Optionnel) **Ollama** pour Savia Shield (`ollama --version`)

## 2. Cloner et premier lancement

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

Au lancement, Savia detecte l'absence de profil et se presente. Repondez a ses questions : nom, role, projets. Cela cree votre profil dans `.claude/profiles/users/{slug}/`.

Si vous voulez sauter le profil : tapez directement une commande. Savia n'insiste pas.

## 3. Configurer votre projet

```bash
/project-new
```

Suivez le wizard. Savia detecte votre outil PM (Azure DevOps, Jira ou Savia Flow) et cree la structure dans `projects/{nom}/`.

Pour Azure DevOps, vous avez besoin d'un PAT enregistre dans `$HOME/.azure/devops-pat` (une seule ligne, sans retour chariot). Scopes : Work Items R/W, Project R, Analytics R.

## 4. Profils de hooks (Savia Shield)

Les hooks controlent quelles regles s'executent automatiquement. Il y a 4 profils :

| Profil | Ce qu'il active | Quand l'utiliser |
|--------|----------------|-----------------|
| `minimal` | Securite de base uniquement | Demos, premiers pas |
| `standard` | Securite + qualite | Travail quotidien (par defaut) |
| `strict` | Securite + qualite + examen supplementaire | Pre-release, code critique |
| `ci` | Comme standard, non interactif | Pipelines CI/CD |

```bash
# Voir le profil actif
bash scripts/hook-profile.sh get

# Changer de profil
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (protection des donnees)

Si vous travaillez avec des donnees clients, activez Savia Shield :

```bash
/savia-shield enable
/savia-shield status
```

Shield protege les donnees sensibles (N4/N4b) contre les fuites vers les fichiers publics (N1). Il fonctionne avec 5 couches : regex, LLM local, audit post-ecriture, masquage reversible et detection base64.

Guide complet : [docs/savia-shield-guide.fr.md](savia-shield-guide.fr.md)

## 6. Cartes : .scm et .ctx

pm-workspace genere deux index navigables :

- **`.scm` (Capability Map)** : catalogue de commandes, skills et agents indexes par intention. Repond a "que peut faire Savia".
- **`.ctx` (Context Index)** : carte indiquant ou vit chaque type d'information (regles, memoire, projets). Repond a "ou chercher ou stocker".

Les deux sont en texte brut, auto-generes, avec chargement progressif (L0/L1/L2).

Statut : en proposition (SPEC-053, SPEC-054). Lorsqu'ils seront disponibles, ils se generent avec :

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Demarrage rapide par role

| Role | Premieres commandes | Routine quotidienne |
|------|---------------------|---------------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PRs, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Chaque role a un guide detaille : `docs/quick-starts/quick-start-{role}.md`

## 8. Reference de configuration

| Quoi configurer | Ou | Exemple |
|-----------------|-----|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Token sur une ligne |
| Profil utilisateur | `.claude/profiles/users/{slug}/` | Cree par `/profile-setup` |
| Profil de hook | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Connecteurs | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Projet outil PM | `projects/{nom}/CLAUDE.md` | Org URL, iteration path |
| Config privee | `CLAUDE.local.md` (gitignored) | Projets reels |

## 9. Performance

- **CLAUDE.md consomme des tokens a chaque tour** (non mis en cache) — gardez-le concis et sous 150 lignes
- **Les skills ne consomment aucun contexte tant qu'ils ne sont pas invoques** — avoir beaucoup de skills est gratuit
- **auto-compact se declenche a 65%** de la fenetre de contexte — executez `/compact` manuellement si vous remarquez une degradation avant
- **Les entrees memoire doivent faire < 150 caracteres** — des resumes courts se chargent plus vite et consomment moins de contexte
- Details complets : `docs/best-practices-claude-code.md`

## 10. Prochaines etapes

1. Executez `/help` pour voir le catalogue interactif de commandes
2. Executez `/daily-routine` pour que Savia vous propose votre routine
3. Lisez le guide de votre role dans `docs/quick-starts/`
4. Si vous utilisez des donnees clients : activez Savia Shield
5. Si quelque chose ne fonctionne pas : `/workspace-doctor` diagnostique l'environnement

---

> Documentation detaillee : `docs/readme/` (13 sections) et `docs/guides/` (15 guides par scenario).
