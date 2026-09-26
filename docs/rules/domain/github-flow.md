---
paths:
  - "**/.github/**"
  - "**/.gitignore"
  - "**/.gitattributes"
---

# GitHub Flow — Reglas de Branching

> Fuente oficial: https://docs.github.com/get-started/quickstart/github-flow

## Principio fundamental

**`main` está siempre deployable.** Nunca se hace commit directamente en `main`.
Todo cambio pasa por una rama + Pull Request + revisión antes de mergear.

---

## Flujo completo

```
main
 └─► feature/nombre-descriptivo   ← crear rama
          │
          ├─ commit  ← trabajo incremental
          ├─ commit
          ├─ push → origin
          │
          └─► Pull Request         ← solicitar revisión
                    │
                    ├─ revisión / comentarios
                    ├─ fix si es necesario
                    │
                    └─► merge a main ← tras aprobación
                              │
                              └─ delete branch
```

---

## Reglas de rama

| Regla | Detalle |
|---|---|
| Nombrar con prefijo | `feature/`, `fix/`, `docs/`, `refactor/`, `chore/` |
| Nombre descriptivo | `feature/agente-architect` no `feature/rama1` |
| Nombre ≤ 5 palabras | Máximo 5 palabras separadas por guiones tras el prefijo (sin contar el `#ID`) |
| ID de tarea DevOps | Si la modificación viene de una tarea o PBI de Azure DevOps, poner `#ID` justo después del prefijo y antes de la descripción (ej: `feature/#12345-crud-sala-reservas`). Esto enlaza automáticamente los commits con la tarea en DevOps |
| Refleja el PBI/tarea | Si existe PBI o tarea, el nombre debe reflejarlo; si no hay tarea DevOps, sintetizar el concepto principal de los cambios |
| Ramas cortas | Merge en días, no semanas; evitar ramas de larga vida |
| Una rama por PBI/tarea | No mezclar cambios no relacionados en la misma rama |

### Prefijos estándar

- `feature/` — nueva funcionalidad o nuevo agente/skill/comando
- `fix/` — corrección de bug o error en configuración
- `docs/` — solo documentación (README, best-practices, reglas)
- `refactor/` — reestructuración sin cambio de comportamiento
- `chore/` — mantenimiento (actualizar .gitignore, limpieza, etc.)
- `release/` — preparación de nueva versión (CHANGELOG, tag)

### Nombrado de rama: regla pre-commit

Antes de hacer commit, verificar que el nombre de la rama actual cumple:
1. **Si existe tarea o PBI en DevOps** → incluir `#ID` tras el prefijo: `feature/#12345-crud-sala-reservas`, `fix/#6789-session-timeout`
2. **Si no existe tarea DevOps** → sintetizar el concepto principal de los cambios más importantes
3. **Máximo 5 palabras** separadas por guiones tras el prefijo (el `#ID` no cuenta como palabra)
4. **Si la rama no cumple** → crear una nueva rama con nombre correcto y mover los cambios

Ejemplos válidos: `feature/#12345-new-test-runner-agent`, `fix/#6789-capacity-formula-edge`, `feature/new-test-runner-agent` (sin tarea DevOps), `docs/align-readme-agent-table`
Ejemplos inválidos: `feature/rama1`, `fix/cosas`, `feature/12345-algo` (falta el `#`), `docs/rename-pm-workspace-and-align-examples-with-current-conventions` (demasiado largo)

---

## Reglas de commit

- Cada commit = un cambio **aislado y completo** (puede revertirse solo)
- Mensaje en imperativo: `add architect agent` · `fix PAT path in pm-config`
- Formato convencional: `tipo(scope): descripción`
  - `feat(agents): add sdd-spec-writer with Opus model`
  - `fix(rules): correct PAT file path reference`
  - `docs(readme): add GitHub Flow section to branching guide`

---

## Pull Request

1. **Abrir PR** desde la feature branch hacia `main`
2. **Título**: igual que el commit principal (convencional, en inglés)
3. **Descripción**: qué cambia y por qué; si cierra un PBI incluir `Closes #N`. Incluir **dos secciones de resumen**: `## Resumen` (español, para el digest que recibe la PM por email) y `## Summary` (inglés, para la comunidad internacional). El digest de PR Guardian prioriza `## Resumen`
4. **Reviewer asignado por tarea**: si la tarea de DevOps que originó el cambio tiene un programador humano asignado (`System.AssignedTo`), ese programador se añade automáticamente como reviewer del PR. Esto garantiza que quien conoce el contexto de la tarea valide el código
5. **Revisión**: con varios colaboradores, solicitar aprobación de un reviewer distinto. Si la operadora es la única colaboradora, puede revisar y mergear su propio PR tras CI y los gates aplicables; GitHub no permite aprobar el PR propio con `gh pr review --approve`. Un agente requiere además grant de merge expreso; tier 3/4 exige revisión humana del PR concreto
6. **Merge**: Squash merge para commits pequeños, Merge commit para features completas. **NUNCA** usar `--admin` para bypass de branch protection
7. **Delete branch**: eliminar la rama tras el merge

---

## Protección de `main`

Configurar en GitHub → Settings → Branches → Branch protection rules:

- Require pull request reviews before merging (1 aprobación) solo si existe reviewer distinto elegible; en un repositorio de una sola colaboradora, este ajuste bloquearía todos sus PRs
- OK Require status checks to pass (build, tests si aplica)
- OK Include administrators (aplica las reglas también al owner)
- OK Delete head branches automatically on merge

---

## Releases y Tags

Toda release usa rama `release/vX.Y.Z` + tag anotado tras merge:

1. `git checkout -b release/vX.Y.Z` desde `main`
2. Actualizar `CHANGELOG.md` con versión y fecha
3. Commit: `chore(release): prepare vX.Y.Z — Título breve`
4. Push + PR hacia `main`
5. Tras merge: `git checkout main && git pull && git tag -a vX.Y.Z -m "vX.Y.Z — Título" && git push origin vX.Y.Z`

**SemVer**: Minor (0.X.0) = nuevos agentes/comandos/skills · Patch (0.0.X) = fixes/docs · Major (X.0.0) = cambios incompatibles

**Prefijo de rama**: `release/` (se añade a los prefijos estándar de la tabla anterior)

## Idioma obligatorio

**Todo contenido versionado y público se escribe en inglés.** Esto incluye:

- `CHANGELOG.md` (raíz y subproyectos)
- Títulos de PR y mensajes de commit
- Nombres de rama
- `README.md`
- Comentarios en código

Excepción: la sección `## Resumen` en PRs es bilingüe (español para la PM + inglés para la comunidad, ver regla de PR arriba).

**Gate CI:** PR Guardian Gate 8 bloquea PRs sin CHANGELOG. El CHANGELOG debe estar en inglés.

---

## En este workspace

Claude Code / OpenCode **nunca** hace commit directamente en `main`. Siempre se parte de `main` y se vuelve a `main`:

1. **Partir de `main`**: `git checkout main && git pull` antes de empezar cualquier tarea
2. **Crear rama**: `git checkout -b feature/#ID-descripcion` si hay tarea DevOps, o `git checkout -b feature/descripcion` si no la hay (nombre ≤ 5 palabras, `#ID` no cuenta)
3. Implementar + commit(s)
4. **Antes de cada commit**: verificar que el nombre de la rama refleja los cambios; si no, crear rama nueva con nombre adecuado
5. **Volver a `main`**: tras el commit, `git checkout main` — la rama queda lista para push/PR pero el workspace vuelve a `main`
6. Desde `main`, la siguiente tarea creará su propia rama nueva

**Regla fundamental: toda tarea empieza en `main` y termina en `main`.**
