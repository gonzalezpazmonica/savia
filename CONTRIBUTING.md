# Contribuir a PM-Workspace

Soy Savia, y me encanta que quieras contribuir. Crezco con el uso real: las mejores contribuciones vienen de gente que encontró algo que le faltaba mientras gestionaba un proyecto de verdad.

Antes de empezar, lee este documento y el [Código de Conducta](CODE_OF_CONDUCT.md).

---

## Qué busco

Las contribuciones de mayor impacto son:

**Nuevos comandos** (`.opencode/commands/`) — si tuviste una conversación conmigo que resolvió un problema PM que aún no cubro, empaquétalo como comando reutilizable. Mira el [ROADMAP.md](docs/ROADMAP.md) para ver qué falta.

**Nuevos skills** (`.opencode/skills/`) — skills que me extiendan a nuevo territorio: integración Jira, metodologías SAFe/Kanban, o nuevos formatos de reporting.

**Tests** — nuevas suites en `tests/`, escenarios de mock, ejemplos de specs.

**Bug fixes** — correcciones en scripts, hooks, o agentes.

**Documentación** — clarificaciones, ejemplos, traducciones. Ahora mismo hablo 9 idiomas.

---

## Quick start

```bash
git clone https://github.com/YOUR-USERNAME/pm-workspace.git
cd pm-workspace
git checkout -b feature/tu-feature
# Haz tus cambios
bash tests/run-all.sh                # Toda la suite debe pasar
bash scripts/validate-ci-local.sh    # CI local
# Abre Pull Request contra main
```

---

## Ramas

| Prefijo | Uso |
|---------|-----|
| `feature/` | Nuevo comando, skill, integración |
| `fix/` | Corrección de bug |
| `docs/` | Solo documentación |
| `test/` | Suite de tests o mock data |
| `refactor/` | Reestructuración sin cambio de comportamiento |

---

## Estándares para comandos y skills

### Comandos (`.opencode/commands/*.md`)

Cada comando nuevo necesita: descripción, pasos numerados, manejo del error más común, al menos un ejemplo, y referencia a skills que usa.

### Skills (`.opencode/skills/*/SKILL.md`)

Cada skill necesita: SKILL.md + DOMAIN.md (Clara Philosophy). Descripción, cuándo usarlo, parámetros, limitaciones.

---

## Testing

```bash
bash tests/run-all.sh              # Suite completa
bats tests/structure/test-X.bats   # Suite individual
```

Mi CI ejecuta estos mismos comandos en cada PR. No mergeo si la suite regresa.

---

## Certificación de origen (DCO)

Cada commit de un Pull Request debe llevar una línea `Signed-off-by: Tu Nombre <tu@email>` con el mismo correo que el autor del commit. Con ella certificas el Developer Certificate of Origin 1.1 (texto íntegro más abajo): que tienes derecho a enviar el código bajo la licencia del proyecto (MIT). No se firma ningún acuerdo de cesión de derechos ni de relicenciación.

```bash
git commit -s -m "feat: mi cambio"          # commit nuevo con Signed-off-by
git commit --amend -s --no-edit             # añadirlo al último commit
git rebase --signoff origin/main            # añadirlo a todos los commits de la rama
git push --force-with-lease                 # tras reescribir tu propia rama
```

El workflow `DCO check` (`.github/workflows/dco-check.yml`) lista los commits del PR y falla nombrando los SHA sin sign-off. Quedan exentos los commits de bots (autor `type: Bot` o login `*[bot]`) y los PRs de ramas `agent/*` abiertos por quien mantiene el repositorio: los agentes no firman en nombre de nadie. Aplica solo hacia adelante; el historial no se reescribe. Esto no es asesoramiento legal.

```text
Developer Certificate of Origin
Version 1.1

Copyright (C) 2004, 2006 The Linux Foundation and its contributors.

Everyone is permitted to copy and distribute verbatim copies of this
license document, but changing it is not allowed.


Developer's Certificate of Origin 1.1

By making a contribution to this project, I certify that:

(a) The contribution was created in whole or in part by me and I
    have the right to submit it under the open source license
    indicated in the file; or

(b) The contribution is based upon previous work that, to the best
    of my knowledge, is covered under an appropriate open source
    license and I have the right under that license to submit that
    work with modifications, whether created in whole or in part
    by me, under the same open source license (unless I am
    permitted to submit under a different license), as indicated
    in the file; or

(c) The contribution was provided directly to me by some other
    person who certified (a), (b) or (c) and I have not modified
    it.

(d) I understand and agree that this project and the contribution
    are public and that a record of the contribution (including all
    personal information I submit with it, including my sign-off) is
    maintained indefinitely and may be redistributed consistent with
    this project or the open source license(s) involved.
```

---

## Pull Requests

Usa la plantilla de `.github/pull_request_template.md`. Rellena todas las secciones.

**Proceso:** un maintainer revisa en 7 días. Espera feedback e iteración — es normal, no es rechazo. Una vez aprobado, se mergea en la siguiente release.

---

## Issues

Usa las plantillas de GitHub (Bug report o Feature request). Incluye: versión de Claude Code, comando o skill involucrado, qué esperabas y qué pasó.

---

## Lo que no acepto

- Credenciales, PATs, URLs de organización, o datos reales de proyecto
- Cambios que rompen la suite de tests sin razón documentada
- Comandos que duplican funcionalidad existente sin mejorarla
- Contribuciones generadas por IA sin testing manual real

---

## Reconocimiento

Cada contributor aparece en [CONTRIBUTORS.md](CONTRIBUTORS.md). Los first-timers se destacan en las release notes.
