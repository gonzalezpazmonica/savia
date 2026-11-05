# Guia de Inicio — pm-workspace

> De cero a productivo en 15 minutos.

---

## 1. Prerequisitos

- **Claude Code / OpenCode** instalado y autenticado (`opencode --version`)
- **Git** >= 2.30 (`git --version`)
- **gh CLI** >= 2.0 para PRs y issues (`gh --version`)
- **jq** para parseo JSON (`jq --version`)
- (Opcional) **Ollama** para Savia Shield (`ollama --version`)

## 2. Clonar y primer arranque

```bash
git clone https://github.com/your-org/pm-workspace.git
cd pm-workspace
claude
```

Al arrancar, Savia detecta que no tienes perfil y se presenta. Responde a sus preguntas: nombre, rol, proyectos. Esto crea tu perfil en `.claude/profiles/users/{slug}/`.

Si quieres saltar el perfil: escribe directamente un comando. Savia no insiste.

## 2b. Instalación completa (funcionalidades nuevas)

El instalador central deja Savia operativa al completo en cualquier ordenador
(idempotente, con log de instalación):

```bash
bash scripts/savia-install.sh            # memory-deps + automations + plugin + merge-drivers
```

El log de cada paso vive en `output/install-logs/` (y `~/.savia/install.log`);
el siguiente arranque lo consulta para auto-corregir lo que haya fallado.

Capacidades que quedan activas desde el primer arranque:

- **SCL (aprendizaje continuo)**: captura → ciclo de vida → métrica L → recall.
- **SAGI (orquestador)**: decidir con LLM local (Ollama) y consolidar aprendizaje cada día.
- **Metacognición (L13)**: la capa que ajusta la confianza de Savia con su historial real (calibración, divergencia, control).
- **Criterio (CRITERIO.md)**: citado y validado en cada decisión.
- **Loops autónomos**: las tareas programadas (orquestador diario, morning brief, drift, CVE, memoria) saltan solas al arrancar la sesión si están atrasadas.

Todas estas capacidades ejecutan en infraestructura propia (CRIT-001); el único
LLM opcional es el local vía Ollama en `127.0.0.1:11434`.

## 3. Configurar tu proyecto

```bash
/project-new
```

Sigue el wizard. Savia detecta tu PM tool (Azure DevOps, Jira, o Savia Flow) y crea la estructura en `projects/{nombre}/`.

Para Azure DevOps, necesitas un PAT guardado en `$HOME/.azure/devops-pat` (una linea, sin salto). Scopes: Work Items R/W, Project R, Analytics R.

## 4. Perfiles de hooks (Savia Shield)

Los hooks controlan que reglas se ejecutan automaticamente. Hay 4 perfiles:

| Perfil | Que activa | Cuando usarlo |
|--------|-----------|---------------|
| `minimal` | Solo seguridad basica | Demos, primeros pasos |
| `standard` | Seguridad + calidad | Trabajo diario (default) |
| `strict` | Seguridad + calidad + scrutinio extra | Pre-release, codigo critico |
| `ci` | Igual que standard, no interactivo | Pipelines CI/CD |

```bash
# Ver perfil activo
bash scripts/hook-profile.sh get

# Cambiar perfil
bash scripts/hook-profile.sh set standard
```

## 5. Savia Shield (proteccion de datos)

Si trabajas con datos de clientes, activa Savia Shield:

```bash
/savia-shield enable
/savia-shield status
```

Shield protege datos sensibles (N4/N4b) de filtrarse a ficheros publicos (N1). Funciona con 5 capas: regex, LLM local, auditoria post-escritura, masking reversible y deteccion base64.

Guia completa: [savia-shield-guide.md](savia-shield-guide.md)

## 6. Mapas: .scm y .ctx

pm-workspace genera dos indices navegables:

- **`.scm` (Capability Map)**: catalogo de comandos, skills y agentes indexados por intencion. Responde a "que puede hacer Savia".
- **`.ctx` (Context Index)**: mapa de donde vive cada tipo de informacion (reglas, memoria, proyectos). Responde a "donde buscar o guardar datos".

Ambos son texto plano, auto-generados, con carga progresiva (L0/L1/L2).

Estado: en propuesta (SPEC-053, SPEC-054). Cuando esten disponibles, se generan con:

```bash
bash scripts/derived.sh ensure --only scm  # .scm
bash scripts/generate-context-index.sh     # .ctx
```

## 7. Quickstart por rol

| Rol | Primeros comandos | Rutina diaria |
|-----|-------------------|---------------|
| **PM** | `/sprint-status`, `/team-workload`, `/daily-routine` | `/async-standup`, `/board-flow` |
| **Tech Lead** | `/arch-health`, `/pr-pending`, `/tech-radar` | `/spec-status`, `/debt-analyze` |
| **Developer** | `/my-sprint`, `/my-focus`, `/dev-session` | PRs, `/spec-implement` |
| **QA** | `/qa-dashboard`, `/testplan-generate` | `/qa-regression-plan`, `/a11y-audit` |
| **Product Owner** | `/kpi-dashboard`, `/backlog-prioritize` | `/feature-impact`, `/capacity-forecast` |
| **CEO / CTO** | `/portfolio-overview`, `/ceo-report` | `/ceo-alerts`, `/governance-audit` |

Cada rol tiene una guia detallada: `docs/quick-starts/quick-start-{rol}.md`

## 8. Referencia de configuracion

| Que configurar | Donde | Ejemplo |
|----------------|-------|---------|
| PAT Azure DevOps | `$HOME/.azure/devops-pat` | Token de una linea |
| Perfil de usuario | `.claude/profiles/users/{slug}/` | Creado por `/profile-setup` |
| Hook profile | `~/.savia/hook-profile` | `standard` |
| Savia Shield | `.claude/settings.local.json` | `SAVIA_SHIELD_ENABLED: true` |
| Conectores | `claude.ai/settings/connectors` | Slack, GitHub, Jira |
| Proyecto PM tool | `projects/{nombre}/CLAUDE.md` | Org URL, iteration path |
| Config privada | `CLAUDE.local.md` (gitignored) | Proyectos reales |

## 9. Rendimiento

- **CLAUDE.md consume tokens en cada turno** (no se cachea) — mantenlo escueto y bajo 150 lineas
- **Los skills no consumen contexto hasta que se invocan** — tener muchos skills es gratis
- **auto-compact se dispara al 65%** de la ventana de contexto — ejecuta `/compact` manualmente si notas degradacion antes
- **Las entradas de memoria deben ser < 150 caracteres** — resúmenes cortos se cargan mas rapido y ocupan menos contexto
- Detalle completo: `docs/best-practices-claude-code.md`

## 10. Siguientes pasos

1. Ejecuta `/help` para ver el catalogo interactivo de comandos
2. Ejecuta `/daily-routine` para que Savia te proponga tu rutina
3. Lee la guia de tu rol en `docs/quick-starts/`
4. Si usas datos de clientes: activa Savia Shield
5. Si algo falla: `/workspace-doctor` diagnostica el entorno

> Documentacion detallada: `docs/readme/` (13 secciones) y `docs/guides/` (15 guias por escenario).
