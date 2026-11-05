# Hasteko Gida — pm-workspace

> Zerotik produktibora 15 minututan.

---

## 1. Aurrebaldintzak

- **Claude Code / OpenCode** instalatuta eta autentikatuta (`claude --version` edo `opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 PRentzat eta issueetarako (`gh --version`)
- **jq** JSON parseatzeko (`jq --version`)
- (Aukerakoa) **Ollama** Savia Shield-erako (`ollama --version`)

## 2. Klonatu eta lehen abiaraztea

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

Abiaraztean, Savia-k detektatzen du profilerik ez duzula eta aurkezten da. Erantzun bere galderak: izena, rola, proiektuak. Honek zure profila sortzen du `.claude/profiles/users/{slug}/` barruan.

Profila saltatu nahi baduzu: idatzi zuzenean komando bat. Savia-k ez du behin eta berriz eskatzen.

## 3. Zure proiektua konfiguratu

```bash
/project-new
```

Jarraitu wizard-a. Savia-k zure PM tresna detektatzen du (Azure DevOps, Jira, edo Savia Flow) eta egitura sortzen du `projects/{izena}/` barruan.

Azure DevOps-erako, PAT bat behar duzu `$HOME/.azure/devops-pat` fitxategian (lerro bat, lerro-jauzirik gabe). Scopes: Work Items R/W, Project R, Analytics R.

## 4. Hook profilak (Savia Shield)

Hook-ek kontrolatzen dute zein arau automatikoki exekutatzen diren. 4 profil daude:

| Profila | Zer aktibatzen du | Noiz erabili |
|---------|-------------------|--------------|
| `minimal` | Oinarrizko segurtasuna bakarrik | Demoak, lehen urratsak |
| `standard` | Segurtasuna + kalitatea | Eguneroko lana (lehenetsia) |
| `strict` | Segurtasuna + kalitatea + azterketa gehigarria | Release aurretik, kode kritikoa |
| `ci` | standard bezala, ez interaktiboa | CI/CD pipeline-ak |

```bash
# Profil aktiboa ikusi
bash scripts/hook-profile.sh get

# Profila aldatu
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (datuen babesa)

Bezeroen datuekin lan egiten baduzu, aktibatu Savia Shield:

```bash
/savia-shield enable
/savia-shield status
```

Shield-ek datu sentikorrak (N4/N4b) fitxategi publikoetara (N1) filtratzea ekiditen du. 5 geruzekin funtzionatzen du: regex, LLM lokala, post-idazketa auditoria, masking itzulgarria eta base64 detekzioa.

Gida osoa: [docs/savia-shield-guide.eu.md](savia-shield-guide.eu.md)

## 6. Mapak: .scm eta .ctx

pm-workspace-k bi indize nabigagarri sortzen ditu:

- **`.scm` (Capability Map)**: komandoen, skill-en eta agenteen katalogoa, asmoz indexatua. "Zer egin dezake Savia-k" galderari erantzuten dio.
- **`.ctx` (Context Index)**: informazio mota bakoitza non dagoen erakusten duen mapa (arauak, memoria, proiektuak). "Non bilatu edo gorde" galderari erantzuten dio.

Biak testu arrunta dira, auto-sortuak, karga progresiboa dutenak (L0/L1/L2).

Egoera: proposamenean (SPEC-053, SPEC-054). Erabilgarri daudenean, honela sortzen dira:

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Quickstart rolaren arabera

| Rola | Lehen komandoak | Eguneroko errutina |
|------|-----------------|-------------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PRak, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Rol bakoitzak gida zehatza du: `docs/quick-starts/quick-start-{rola}.md`

## 8. Konfigurazio erreferentzia

| Zer konfiguratu | Non | Adibidea |
|-----------------|-----|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Lerro bakarreko tokena |
| Erabiltzaile profila | `.claude/profiles/users/{slug}/` | `/profile-setup`-ek sortua |
| Hook profila | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Konektoreak | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Proiektu PM tresna | `projects/{izena}/CLAUDE.md` | Org URL, iteration path |
| Konfigurazio pribatua | `CLAUDE.local.md` (gitignored) | Benetako proiektuak |

## 9. Errendimendua

- **CLAUDE.md-k tokenak kontsumitzen ditu txanda bakoitzean** (ez da cacheatzen) — mantendu txukun eta 150 lerro azpitik
- **Skill-ek ez dute testuingururik kontsumitzen deitu arte** — skill asko izatea doakoa da
- **auto-compact %65ean aktibatzen da** testuinguru-leihoan — exekutatu `/compact` eskuz degradazioa lehenago nabaritzen baduzu
- **Memoria-sarrerek < 150 karaktere izan behar dute** — laburpen laburrak azkarrago kargatzen dira eta testuinguru gutxiago hartzen dute
- Xehetasun osoa: `docs/best-practices-claude-code.md`

## 10. Hurrengo urratsak

1. Exekutatu `/help` komando-katalogo interaktiboa ikusteko
2. Exekutatu `/daily-routine` Savia-k zure errutina proposatzeko
3. Irakurri zure rolaren gida `docs/quick-starts/` barruan
4. Bezeroen datuekin lan egiten baduzu: aktibatu Savia Shield
5. Zerbait huts egiten badu: `/workspace-doctor` ingurunea diagnostikatzen du

---

> Dokumentazio zehatza: `docs/readme/` (13 atal) eta `docs/guides/` (15 gida eszenariotik).
