# Spec: SE-260 — gentle-ai v1.49 Patterns (4 slices)

**Status:** IMPLEMENTED (PR #903, 2026-07-11)
**Fecha:** 2026-07-11
**Area:** Review lifecycle / Delegation economics / Artifact lifecycle / Gates
**Branch:** agent/se260-gentle-patterns
**Estimacion total:** ~24h (4 slices independientes)
**Inspirado por:** gentle-ai v1.49.0 (Gentleman-Programming, release 2026-07-10, PRs #1098/#1100/#1101/#1106)

**Developer Type:** agent-team
**Asignado a:** claude-agent-team
**Estado:** Implementado

**Effort Estimation (Dual Model):**
| Dimension | Value |
|-----------|-------|
| Agent effort | 24h (4 slices) |
| Human effort | 6h (revision por slice + decision final) |
| Review effort | 4h |
| Context risk | medium |
| Agent-capable | partial |
| Fallback | Si agente falla: humano necesita ~20h desde cero |

**OpenCode Implementation Plan:**
| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Court rules YAML | rules/court.rules.yaml | Mismo fichero |
| Delegacion nativa | config/native-delegation.yaml | Plugin savia-foundation.ts |
| Artefactos | Python lib managed-artifacts/ | Misma lib |
| Recibos v2 | scripts/receipt-v2.sh + pr-plan.sh | Mismo hook (bash) |

**Portability classification:** DUAL_BINDING — logica core portable (bash/Python/YAML); S2 depende explicitamente de OpenCode.

---

## Origen

Analisis de la release v1.49.0 de gentle-ai (2026-07-10) cruzado contra
Savia v6.15.0 (HEAD 115effbb, #901). La release de gentle-ai ataca un
problema que Savia tiene medido y sin resolver: el coste de los ciclos de
revision. Cuatro ideas adaptadas:

1. **Ciclo de revision acotado ("review once, fix once")** — gentle-ai #1106
2. **Delegacion nativa a OpenCode** — gentle-ai #1100
3. **Ciclo de vida ownership-safe de artefactos** — gentle-ai #1101
4. **Recibos de revision ligados a contenido** — gentle-ai #1098

Cada slice se sostiene solo con problema propio medible en Savia; si
gentle-ai desapareciera mañana, los cuatro seguiran justificados.

**No portado:** empaquetado GoReleaser/Homebrew/Scoop, CLI gentle-ai, sistema de perfiles.

---

## Objetivo

Acotar el ciclo del Court a una-revision-un-fix con freeze verificable (S1),
abaratar la exploracion delegandola al agente nativo con frontera
deny-by-default (S2), unificar los instaladores propios bajo un contrato
ownership-safe con uninstall real (S3), y hacer los sellos de revision
durables por contenido (S4).

---

## Infraestructura existente (baseline pre-implementacion)

| Componente | Path | Estado |
|---|---|---|
| Court orquestador | `.opencode/agents/court-orchestrator.md` | Existe, max 3 fix rounds, scoring formula |
| Court review helper | `scripts/court-review.sh` | Existe, batch-size gate, skeleton, score, hash |
| PR plan gates | `scripts/pr-plan.sh` + `scripts/pr-plan-gates.sh` | Existe, 17 gates G0-G15, `.pr-plan-ok` sentinel |
| Push PR | `scripts/push-pr.sh` | Existe, consume `.pr-plan-ok` |
| Plugin guards | `.opencode/plugins/savia-foundation.ts` | Existe, 22 guards TS |
| Delegation hooks | `.opencode/hooks/delegation-guard.sh` | Existe, bloquea recursion |
| Install git hooks | `scripts/install-git-hooks.sh` | Existe, 3 hooks, backup timestamp |
| Init script | `.opencode/init-pm.sh` | Existe, carga vars de entorno |
| Configurator agent | `.opencode/agents/configurator.md` | Existe, dispatch heuristics |

**Gaps detectados:**
- `rules/court.rules.yaml` — NO existe. El presupuesto de fix y el path-set canonico son nuevos.
- `config/native-delegation.yaml` — NO existe.
- `gate-signed` — NO existe. Solo `.pr-plan-ok` (empty file sentinel).
- No hay systemd units (correccion: el spec original asumia units que no existen).
- No hay auto-install de artefactos; `install-git-hooks.sh` es manual.

---

## Slice 4 — Recibos de revision ligados a contenido (PRIMERO: 4h)

### Delta correctivo 2026-09-08 — raiz del gate G0b

**RCA:** `pr-plan.sh` define `ROOT`, pero `g0b()` construye la ruta del
verificador con la variable inexistente `PRJ`. Bajo `set -u`, el gate emite
`PRJ: unbound variable` y el wrapper lo interpreta como salida no bloqueante.

**Criterio adicional AC-4.7:** G0b debe resolver `receipt-v2.sh` desde `ROOT`,
ejecutarse sin variables no ligadas y conservar el flujo compatible cuando no
existe recibo.

**Implantación:** corregido en `scripts/pr-plan-gates.sh`; regresión ejecutable
en `tests/test-se-260-s4-receipts.bats` (2026-09-08). Revisión E1 pendiente.

El encabezado seguía marcando `PROPOSED/Pendiente` aunque las cuatro slices
se integraron en PR #903 y el roadmap ya las registra como implementadas; se
reconcilia ese drift documental sin crear una aprobación nueva.

**Problema:** `.pr-plan-ok` es un fichero vacio que se invalida con cualquier
rebase/amend aunque el contenido revisado no cambie. Re-revisiones sin cambio
real = friccion y tokens perdidos.

**Estado actual:** `pr-plan.sh` (96 lines) ejecuta 17 gates y toca `.pr-plan-ok`
al pasar todos. `push-pr.sh` (165 lines) verifica que `.pr-plan-ok` existe y
advierte si hay commits nuevos tras el plan. Es un sentinel de instante/worktree,
no de contenido.

**Diseño:**
- **Recibo v2**: al pasar el plan, se persiste `scripts/receipt-v2.sh sign` que
  genera `output/receipts/<branch>.receipt.json` con: `{path_set, patch_ids (git
  patch-id --stable por cada path), tree_hash, veredicto, ts, firma}`. El
  recibo vive junto al estado del PR, no en el worktree.
- **Normalizacion declarada**: antes de calcular patch-id, se aplica
  `git -c core.autocrlf=input -c core.whitespace=trailing-space,space-before-tab`
  para que el hash sea estable cross-entorno. Documentado en el propio recibo
  (campo `normalization`).
- **Validacion pre-push/pr-guardian**: `scripts/receipt-v2.sh verify` recalcula
  patch-ids sobre los paths del recibo. Coinciden todos → valido aunque SHA
  cambio (rebase, amend de mensaje, squash). Un solo path difiere → invalido.
  Path nuevo fuera del set → señalado como no-cubierto (ni falso bloqueo ni
  falso pase).
- **Cadena de integracion**: `receipt-v2.sh verify` se inserta como gate G0b en
  `pr-plan-gates.sh`, entre G0 (previous failure check) y G1 (branch safety).
  Si el recibo es valido para los paths revisados, G0b pasa y el plan no
  re-ejecuta gates para esos paths (solo gates estructurales G1-G3).
- **Convivencia**: `.pr-plan-ok` sigue existiendo para PRs sin recibo v2.
  `receipt-v2.sh verify` comprueba primero si existe recibo; si no, delega
  en el flujo `.pr-plan-ok` original. Los nuevos PRs nacen v2.

**Acceptance criteria:**

AC-4.1. Rebase sin cambio de contenido sobre PR con recibo → `receipt-v2.sh
        verify` retorna 0, pre-push pasa sin re-ejecutar gates de contenido.
AC-4.2. Cambio de 1 byte en un path revisado → `verify` retorna 1, gate exige
        re-plan completo (test con archivo sintetico).
AC-4.3. Path nuevo añadido FUERA del path-set → `verify` retorna 0 (recibo
        valido para lo revisado) y emite WARN listando paths no cubiertos.
        G1-G3 (branch, tree, merge) se ejecutan igual.
AC-4.4. Amend solo de mensaje de commit → recibo valido (test: mismo contenido,
        distinto SHA de commit).
AC-4.5. Hash estable cross-entorno: mismo contenido en dos checkouts limpios
        → mismo patch-id (test en CI con dos jobs o dos clones locales).
AC-4.6. `receipt-v2.sh verify` sin recibo previo → exit 0 con mensaje
        "no receipt found, full plan required", delega al flujo original
        (backward compatible).

**Esfuerzo:** 4h

**Ficheros:**
| Accion | Path |
|--------|------|
| CREATE | `scripts/receipt-v2.sh` |
| CREATE | `output/receipts/` (directory) |
| MODIFY | `scripts/pr-plan-gates.sh` (add G0b gate) |
| CREATE | `tests/test-se-260-s4-receipts.bats` |

---

## Slice 1 — Ciclo de revision acotado del Court (SEGUNDO: 10h)

**Problema:** el Court puede iterar revision→fix→re-revision sin limite
estructural; cada iteracion re-descubre, amplia hallazgos y quema tokens.
El court-orchestrator actual tiene "max 3 fix rounds" pero sin path-set
canonico, sin freeze de hallazgos, y sin verificacion dirigida.

**Estado actual:** `court-orchestrator.md` (130 lines) orquesta 5 jueces en
paralelo, scoring formula, produce `.review.crc`. `court-review.sh` (118 lines)
maneja check/skeleton/score/hash. `fix-assigner.md` lee `.review.crc` y crea
tasks. NO existe `rules/court.rules.yaml`.

**Diseño:**
- **`rules/court.rules.yaml`** — nuevo fichero de configuracion con schema:
```yaml
version: 1
budget:
  max_fix_turns: 3
  max_fix_tokens: 12000
  timeout_per_judge_seconds: 60
freeze:
  auto_freeze_after_first_pass: true
  allow_operator_override: true
escalation:
  contradiction_handler: escalate_to_operator
  late_findings: follow_up_queue
verification:
  mode: directed  # no discovery pass after freeze
  recheck_original_acs: true
  recheck_fixed_findings_only: true
paths:
  derive_from: "git diff base..HEAD --name-only"
  exclude_patterns: ["CHANGELOG.md", ".scm/*"]
```
- **Path-set canonico**: al abrir revision, el orquestador deriva de
  `git merge-base main HEAD`..HEAD el path-set y lo persiste en
  `.review.crc` (campo nuevo `paths:`). Fuente: git, no argumentos.
- **Freeze de hallazgos**: tras la primera pasada de todos los jueces, los
  hallazgos bloqueantes se congelan en `.review.crc` con `status: frozen`.
  El presupuesto se declara (3 turns, 12000 tokens).
- **Fix acotado**: guard via `scope-guard.sh` (ya existe, 105 lines)
  adaptado para modo court: si el fix toca un path fuera del path-set, falla
  antes de mutar. NO consume presupuesto.
- **Verificacion dirigida**: tras el fix, los jueces reciben mandato
  `mode: verify` con lista de findings a re-chequear + ACs originales.
  Prohibida la segunda pasada de descubrimiento.
- **Follow-ups**: hallazgos post-freeze van a `.review.crc` seccion
  `follow_ups` no bloqueante. Visibles en PR body. Comando `/court-followup
  <id>` los convierte en PBI.
- **Contradiccion escala**: fix que invalida un frozen finding → el
  orquestador empaqueta el conflicto (ambas posiciones + evidencia) y
  escala a la operadora. Jamas re-abre el bucle solo.
- **Paridad por catalogo**: test parametrizado sobre el catalogo de jueces
  (patron `agent-sync-check`). Juez nuevo sin contrato → test rojo.

**Acceptance criteria:**

AC-1.1. E2E sobre PR sintetico: una revision, un freeze, un fix, una
        verificacion dirigida, cierre. Cero segundas pasadas de
        descubrimiento (verificado por `mode:` en mandatos de jueces).
AC-1.2. Fix fuera del path-set → bloqueado por scope-guard antes de
        mutacion; presupuesto inalterado.
AC-1.3. Hallazgo tardio post-freeze → seccion `follow_ups` en `.review.crc`;
        contadores de turnos/tokens inalterados.
AC-1.4. Contradiccion sintetica → escalada empaquetada con `escalation:
        contradiction` en `.review.crc`; cero re-aperturas.
AC-1.5. `rules/court.rules.yaml` existe y es validable (schema check).
AC-1.6. Test de paridad: juez sin entry en rules → rojo.

**Esfuerzo:** 10h

**Ficheros:**
| Accion | Path |
|--------|------|
| CREATE | `rules/court.rules.yaml` |
| MODIFY | `.opencode/agents/court-orchestrator.md` |
| MODIFY | `scripts/court-review.sh` |
| MODIFY | `.opencode/hooks/scope-guard.sh` |
| CREATE | `tests/test-se-260-s1-court-cycle.bats` |

---

## Slice 2 — Delegacion nativa a OpenCode con frontera deny-by-default (TERCERO: 4h)

**Problema:** toda exploracion paga el contexto completo de un agente Savia;
el agente nativo `explore` de OpenCode no paga ese indice de contexto. El
agente `general` nativo tiene write access — peligroso sin scoping.

**Estado actual:** `savia-foundation.ts` (173 lines) registra 22 guards.
`delegation-guard.sh` bloquea recursion. `configurator.md` decide que agentes
invocar. NO existe `config/native-delegation.yaml`.

**Diseño:**
- **`config/native-delegation.yaml`** — allowlist declarativa:
```yaml
version: 1
native_agents:
  explore:
    allow: true
    scope: read_only
    description: "Codebase exploration, file search, architecture discovery"
    max_turns: 10
  general:
    allow: false
    reason: "general tiene write access; usar solo bajo autorizacion explicita"
default: deny
```
  NOTA: `general` queda denegado por defecto (tiene write access). Solo
  `explore` esta en la allowlist. Esto es mas restrictivo que el spec
  original (que sugeria `general` para tareas fuera de flujos gobernados).
- **Router en savia-foundation.ts**: nuevo guard `native-delegation-router.ts`
  que intercepta Task tool calls. Si el target es `explore` o `general` de
  OpenCode, consulta la allowlist. Si el target es un agente Savia, no
  interviene.
- **Frontera de seguridad**: test explicito (AC-2.4) demuestra que los guards
  existentes (sovereignty, credential-leak, prompt-injection) aplican al
  nativo delegado via `tool.execute.before`.
- **Los perfiles y orquestadores generados** preservan la frontera: el
  configurator lee `native-delegation.yaml` y lo refleja en sus decisiones.

**Acceptance criteria:**

AC-2.1. Exploracion de benchmark via nativo `explore`: tokens totales >=50%
        menores que mismo mandato via agente Savia (medicion commiteada en
        `output/benchmarks/s2-native-delegation.json`).
AC-2.2. Invocacion a `general` → denegado con mensaje citando allowlist.
AC-2.3. Dentro de flujo Court/SDD/Judgment activo, el router NO delega
        (test: misma peticion dentro y fuera toma caminos distintos).
AC-2.4. Guard de soberania dispara sobre accion del nativo que toca ruta
        N3 sintetica (frontera aplica al delegado).
AC-2.5. Perfil regenerado contiene allowlist identica a YAML (drift-check).

**Esfuerzo:** 4h

**Ficheros:**
| Accion | Path |
|--------|------|
| CREATE | `config/native-delegation.yaml` |
| CREATE | `.opencode/plugins/guards/native-delegation-router.ts` |
| CREATE | `tests/test-se-260-s2-native-delegation.bats` |

---

## Slice 3 — Contrato ownership-safe para artefactos gestionados (CUARTO: 6h)

**Problema:** instaladores heterogeneos (git hooks, symlinks) sin contrato
comun: uninstall parcial o ausente, sin health probe uniforme, riesgo de
pisar ficheros ajenos.

**Correccion del spec original:** no existen systemd units (bridge, watchdog).
Los artefactos gestionados reales son:
1. Git hooks en `.git/hooks/` (instalados por `install-git-hooks.sh`)
2. Symlinks `.opencode/` → `.claude/` (commands, hooks, skills, docs)
3. Mapas ACM `.agent-maps/` (si aplica)

**Estado actual:** `scripts/install-git-hooks.sh` (109 lines) instala 3 hooks
con backup timestamp. `init-pm.sh` carga vars pero no instala artefactos.
No hay health probe, no hay uninstall automatizado, no hay contrato comun.

**Diseño:**
- **`docs/managed-artifacts-contract.md`** — especifica el contrato:
  - `init(root)` — valida raiz canonica (git repo, estructura esperada)
  - `install()` — ownership check: si el target existe sin marker del
    instalador → abortar. Si existe con marker → backup + reemplazar. Si no
    existe → crear. Tras escribir, insertar marker `# managed-by: savia
    <artifact-id> <version> <timestamp>`.
  - `sync()` — idempotente: compara contenido instalado vs template. Si
    difiere, reinstala. Dos ejecuciones → cero diff.
  - `uninstall()` — restaura backup byte a byte. Si no hay backup, elimina
    solo si tiene marker propio. Sin marker → abortar (no tocar ficheros
    ajenos).
  - `probe()` — health check: verifica que el artefacto existe, tiene el
    marker correcto, y el contenido coincide con template. Exit 0 = healthy,
    exit 1 = degraded, exit 2 = missing.
  - `backup()` — copia pre-mutacion a `output/artifacts-backup/<id>/<ts>/`.
- **Libreria Python `scripts/lib/managed_artifacts.py`** — implementa las 6
  operaciones del contrato como modulo reutilizable.
- **Adaptacion de `install-git-hooks.sh`** — wrappea la libreria Python para
  sus 3 hooks, añadiendo markers, backup pre-instalacion, y probe.
- **Integracion con self-audit**: el probe de cada artefacto se registra en
  `scripts/self-audit.sh` (SE-258 S3). Artefacto degraded → hallazgo en
  el informe mensual.
- **Inventario inicial**: `docs/managed-artifacts-inventory.md` lista los 3
  artefactos conocidos con estado (adapted|justified-out).

**Acceptance criteria:**

AC-3.1. Contrato publicado (`docs/managed-artifacts-contract.md`) +
        inventario (`docs/managed-artifacts-inventory.md`) completo.
AC-3.2. `install()` sobre fichero ajeno sin marker → aborta sin tocarlo
        (test byte a byte: diff before/after = vacio).
AC-3.3. `uninstall()` restaura estado previo exacto (test con snapshot
        antes/despues: diff = vacio).
AC-3.4. `sync()` idempotente (2 ejecuciones → segunda no modifica nada,
        diff = vacio) y `probe()` fails-closed (dependencia rota simulada
        → exit != 0).
AC-3.5. Probes integrados en self-audit: artefacto degradado plantado →
        aparece en output del audit.

**Esfuerzo:** 6h

**Ficheros:**
| Accion | Path |
|--------|------|
| CREATE | `docs/managed-artifacts-contract.md` |
| CREATE | `docs/managed-artifacts-inventory.md` |
| CREATE | `scripts/lib/managed_artifacts.py` |
| MODIFY | `scripts/install-git-hooks.sh` |
| CREATE | `tests/test-se-260-s3-artifacts.bats` |

---

## Verification method (cross-slice)

1. **Benchmark S4**: PR sintetico → sign → rebase → verify → OK (sin re-plan).
2. **Benchmark S1**: PR de referencia con Court → tokens antes/despues commiteado.
3. **Benchmark S2**: mandato de exploracion nativo vs Savia → tokens commiteado.
4. **Inventario S3**: 3 artefactos listados, probes funcionales en self-audit.
5. **Suite completa** en verde; gate de archivo SE-258 S4 aplicado al cierre.

## Riesgos (con mitigaciones concretas)

| ID | Riesgo | Slice | Mitigacion |
|----|--------|-------|------------|
| R1 | Un fix insuficiente para hallazgos complejos | S1 | Escalada a operadora con opcion de presupuesto extendido (humano decide, registrado) |
| R2 | Freeze entierra hallazgos tardios legitimos | S1 | Follow-ups visibles en PR + conversion a PBI en 1 comando; metrica mensual en self-audit |
| R3 | Nativo explora fuera de limites Savia | S2 | AC-2.4 demuestra guards; explore es read-only; allowlist se vacia con 1 commit |
| R4 | Adaptar instaladores rompe instalaciones vivas | S3 | Modo migracion con adopcion de markers sin reinstalar; drill en contenedor primero |
| R5 | patch-id inestable por line-endings | S4 | Normalizacion declarada + AC-4.5 cross-entorno; fallback a tree-hash documentado |
| R6 | general nativo tiene write access | S2 | Denegado por defecto en allowlist; solo explore (read-only) habilitado |

## Orden de implementacion

**S4 → S1 → S2 → S3**

S4 primero (4h) porque elimina friccion inmediata (rebase no invalida revision)
y abarata todos los demas slices. S1 segundo (10h) porque es el mayor ahorro
estructural. S2 y S3 son independientes entre si.

## Decision de adopcion

Adoptar slice si: benchmarks alcanzados, ACs en verde, cero regresiones en
suite. Cada slice abandonable con registro en specs-archive.

## Referencias

- gentle-ai v1.49.0 (2026-07-10): PRs #1106, #1100, #1101, #1098.
- Savia: `.opencode/agents/court-orchestrator.md`, `scripts/pr-plan.sh`,
  `scripts/pr-plan-gates.sh`, `scripts/push-pr.sh`, `scripts/install-git-hooks.sh`,
  `.opencode/plugins/savia-foundation.ts`, `scripts/self-audit.sh`.
