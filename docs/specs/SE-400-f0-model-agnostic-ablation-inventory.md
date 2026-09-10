---
id: SE-400-F0
parent: SE-400
status: READY_FOR_HUMAN_REVIEW
created: 2026-09-10
evidence_type: deterministic-repository-inventory
head: 8cf6c4bf3e3c38f6902df7ad55472674d860f016
---

# SE-400 F0 — Model-Agnostic Ablation Inventory

## Estado

F0 completado sobre `origin/main` `8cf6c4bf`. SE-400 estaba libre en las
fuentes locales consultables. No se ha ejecutado F1 ni se ha borrado, movido,
deprecado, empaquetado o retirado del hot path ningún artefacto.

| Campo | Valor |
|---|---|
| HEAD | `8cf6c4bf3e3c38f6902df7ad55472674d860f016` |
| Spec ID/path | `SE-400` / `docs/specs/SE-400-model-agnostic-ablation-minimal-kernel.spec.md` |
| SAM revision | `NOT_IMPLEMENTED`; SE-397 F0 aprobado con concerns |
| SCM state | `FRESH`, registry v1, 1.464 resources |
| SCM index hash | `8587656a0527` |
| SCM content hash | `a0de0dd6a204` |
| Veredicto | `GO_WITH_CONCERNS`; F1 requiere revisión humana |

Los dos hashes SCM representan serializaciones distintas y su diferencia no
es drift. Repos o registries externos no presentes quedan `UNKNOWN`.

## Current surface

| Unidad | Física verificada | Indexada / observación |
|---|---:|---|
| Commands Markdown | 580 | 295 core; 272 extended y 13 references no son capabilities core indexadas |
| Skills | 136 sources válidas | 136 |
| Agent Markdown | 94 ficheros en directorio | 89 definiciones indexadas; otros assets no cuentan como agents |
| Scripts | 1.267 ficheros | 944 shell resources indexados |
| Hooks shell | 126 | kind diferido; 122 entradas parseadas de settings y 119 comandos únicos |
| Rules Markdown | 308 según inventario canónico F0 | kind diferido; manifests tracked están stale |
| Generated views | múltiples | inventario abajo; no son capabilities por defecto |
| Legacy assets | no cuantificable aún | `pm-workspace` aparece en 753 ficheros; mezcla runtime, distribución, historia y fixtures |

SCM registra 1.464 resources: 295 commands, 136 skills, 89 agents y 944
scripts. Todos figuran `active`; cero declaran `depends_on` o `tests`, y solo
89 tienen risk. Su categoría es heurística y cae en planning por defecto, por
lo que no es una taxonomía semántica.

La superficie script física incluye 966 `.sh`, 254 `.py`, 8 `.ts`, 6 `.js`,
4 `.ps1` y otros formatos. El generator solo considera shell top-level o a
profundidad uno: 11 shell más profundos y 11 sin descripción elegible quedan
fuera; Python/TS/JS/PowerShell tampoco se indexan. Esto prueba que
`RESOURCE_COUNT != CAPABILITY_COUNT`, no cuántas capabilities únicas existen.

## Resource vs capability

| Clase | Resultado F0 |
|---|---|
| Canonical capabilities | `UNKNOWN`; SCM contiene resources, no equivalencia semántica |
| Implementation resources | al menos parte de los 1.267 scripts; cifra exacta `NOT_VERIFIED` |
| Projections | SCM, AGENTS, SKILLS, resolver/indexes/manifests y mirrors son candidatos estructurales |
| Aliases | commands extended/core requieren auditoría por familias; cifra `UNKNOWN` |
| Controls | rules, hooks, validators y courts existen; unique failure coverage pendiente |
| Generated views | varias confirmadas; freshness desigual |
| Unknown | semantic overlap, criticality, consumers, usage, latency, runtime reachability y replacements |

No se responde todavía cuántas capabilities semánticas tiene Savia: hacerlo
desde filenames, stems o Jaccard sería falsa precisión.

## Current canonicality

- Claude-owned truth candidate: commands, skills, settings/hooks y parte de
  instructions bajo `.claude`.
- OpenCode-owned truth candidate: 89 agent definitions y plugins bajo
  `.opencode`.
- Codex projection: AGENTS y `.agents/skills`; no hay source canónica Codex
  equivalente demostrada.
- Runtime-neutral truth existente: laws/policy/authority/risk, SCM generator,
  contracts de dual-cli y documentación canónica compartida.
- Manual sync surfaces: README counters/translations, resolver, rule manifests,
  catalog/indexes y compatibility mirrors requieren clasificación por owner.

`AGENTS.md`, `SKILLS.md`, `agents-catalog.md`, `docs/rules/INDEX.md`, SCM y
planning pasan sus checks actuales. `docs/RESOLVER.md` está stale: esperaba
135 skills/89 agents, mientras su bloque tracked refleja 126/83. El rule
manifest de `docs/rules/domain` tiene 305 frente a 308 rules y omite tres; el
mirror `.claude/rules/domain/rule-manifest.json` contiene 110.

## Current debt reconciliation

### SE-376

`APPROVED`, pero su inventory contiene 132 skills frente a 136 actuales. Faltan
template, knowledge-graph, social-linkedin y ubiquitous-language. Las 8
clasificaciones DELETE históricas no son ejecutables: el propio budget prohíbe
auto-delete y requieren consumers/evidence frescos.

### SE-380

`APPROVED/IMPLEMENTING`. Entropy check: 1.634 frente a baseline 1.623 (+11),
por lo que falla el budget actual. El advisor produce 37 señales heurísticas:
8 DEPRECATE, 28 GENERALIZE por stem y 1 MERGE por Jaccard. Son propose-only. El
usage report ve cero invocaciones cuando faltan datos locales; ausencia de
telemetría no significa unused. Lifecycle obligatorio no está poblado y SCM
fuerza casi todo a active.

### SE-387

Umbrella `IMPLEMENTING`. Debt wave 2 y entropy v1/calibration siguen abiertos.
Generated truth es parcial porque resolver/rule manifests están stale. Sus
reglas exigen replacement, migration e intent preservation y prohíben removal
automático.

### SE-397

F0 `APPROVED_WITH_CONCERNS`; SAM continúa `NOT_IMPLEMENTED`. SCM es una
proyección reutilizable, no el architecture model ni una fuente suficiente de
dependencies/authority/evidence.

### Stale classifications

Confirmado stale: resolver, ambos rule manifests, inventory SE-376 y entropy
baseline respecto al crecimiento actual. No se confirma stale/dead para
ninguna capability individual, los 37 advisor candidates, hooks no configurados,
272 extended commands ni scripts no-shell. Confirmed removal candidates: cero.

## Core candidates

| Candidate | Razón/contrato | Dependencias/evidencia |
|---|---|---|
| identity + constitutional rules | identity/authority floors | laws/rules; impact SAM pendiente |
| canonical effects + policy + Human Gates | authority/effect correctness | SE-396/397; runtime parity incompleta |
| runtime execution contracts | portability/fail-safe | adapters y dual-cli; Desktop no verificado |
| evidence/receipts/provenance | evidence integrity | mecanismos existentes dispersos |
| SCM/SAM discovery | capability/architecture query | SCM fresco; SAM no implementado |
| integrity doctor + recovery | failure safety | doctor/canaries existentes |
| minimal context bootstrap | identity/context discipline | corpus de ablación pendiente |

Los 295 commands `tier: core` son únicamente candidatos según metadata. El
subconjunto operacional realmente esencial permanece `UNKNOWN`.

## Pack candidates

| Candidate | Domain | Kernel dependency | Razón provisional |
|---|---|---|---|
| 272 extended commands | multi-domain | unknown | excluidos deliberadamente del core SCM |
| 136 skills on-demand | multi-domain | unknown | lazy/on-demand no significa obsolete |
| professional-domain | legal/finance/labour/sales | unknown | conocimiento vertical explícito |
| project/security/research families | workflow/domain | unknown | deben probar kernel + pack reconstruction |

`config/domain-packs.json` se reutiliza; no se crea otro registry de packs.

## Projection candidates

| Candidate | Canonical origin | Surface | Razón |
|---|---|---|---|
| `.scm/*` | SCM generator/sources | cross-runtime | generated capability views |
| `AGENTS.md` / agent catalog | `.opencode/agents` hoy | Codex/consumer docs | mirrors generados |
| `SKILLS.md` / resolver | `.claude/skills` hoy | cross-runtime | catalogs; resolver stale |
| rules indexes/manifests | canonical rules | Claude/docs | freshness divergente |
| README/ROADMAP counters | registries/planning | user docs | manual-sync candidate |

Canonical origins frontend-specific son deuda arquitectónica, no permiso para
moverlos antes de SAM/projection parity.

## Hot-path candidates

| Mecanismo | Clasificación provisional | Blocking today | Ablation mode |
|---|---|---|---|
| PreToolUse entries (49) | enforcement/unknown mix | configured | A4 after failure matrix |
| PostToolUse entries (38) | evidence/observability mix | configured | A4 batch/async probe |
| remaining configured hooks | lifecycle/advisory/maintenance | mixed | A0/A4 after trace |
| OpenCode settings bridge | runtime projection | partial | A3 projection parity |

122 entries de settings y 119 command strings únicos describen configuración,
no frecuencia, coste ni invocación real. Cuatro hook files directos no aparecen
configurados, pero su dormancy/consumers son `UNKNOWN`.

## Legacy candidates

| Artifact | Consumer | Compatibility required | Recommended action |
|---|---|---|---|
| `.claude/agents` mirror | Claude/legacy consumers unknown | likely partial | trace consumers before projection change |
| active `pm-workspace` runtime/install paths | installers/scripts/config | yes until migrated | classify LIVE_RUNTIME/DISTRIBUTION first |
| historical `pm-workspace` docs | readers/history | preserve | archive or mark historical, not blind replace |
| stale generated catalogs/manifests | tooling/users | yes | regenerate from authority, add checks |

`pm-workspace` aparece en 753 ficheros y 2.346 líneas del audit scope. El dato
mezcla 334 docs, 179 `.claude`, 104 scripts, 39 projects, 26 tests y 16
`.opencode`, entre otros. No es un removal count.

## Ablation experiment backlog

1. **Baseline normalization / A0:** preregistrar scopes por kind, tier,
   profundidad y lenguaje; expected gain = conteos reproducibles; abort si
   cambia SCM/discovery sin explicación.
2. **Generated truth / A3:** regenerar y validar resolver/manifests en sandbox;
   expected loss = ninguna capability; abort ante consumer mismatch.
3. **SE-376 candidates / A0-A3:** actualizar 136 skills y probar uno a uno los
   ocho DELETE históricos; abort ante pérdida de intent/consumer/test.
4. **Entropy / control:** calibrar v1 sin subir baseline para absorber +11;
   entropy nunca decide removal.
5. **Advisor 37 / A3:** consumer/dependency/contract/failure evidence por
   candidato; stems/Jaccard son solo hypothesis.
6. **Extended commands / A0/A5:** medir routing/discovery y reconstrucción como
   packs; model variable, corpus multi-intent.
7. **Scripts gap / A0:** clasificar 323 no-shell y 22 shell fuera del índice;
   no asumir que indexar más equivale a más capability.
8. **Hooks / A4:** event→hook/failure matrix, latency y fault injection;
   abort inmediato ante false allow/authority/security delta.
9. **Runtime projections / A3:** trace consumers de mirrors y verificar parity
   Claude/OpenCode/Codex.
10. **Identity residue / A0/A3:** clasificar 753 ficheros por live,
    distribution, generated, historical y fixture antes de cambios.

Todos los experimentos comparan control/variant, preservan negative results y
ligan receipts al HEAD. LLM-mediated trials requieren panel y paired repeats;
ningún modelo es baseline.

## F1 minimum slice

Definir schema read-only de clasificación Resource/Capability/Mechanism/
Projection/Control/View/Pack y baseline contract versionado, extendiendo
SE-397/SCM en vez de crear otro graph. Generar un inventory report reproducible
con provenance/freshness y `UNKNOWN`; no mover archivos ni ejecutar removals.

Complejidad estimada: media, dependiente de decidir junto a SE-397 F1 y de
corregir primero las vistas generadas stale.

## Human decisions required

1. Aprobar F0 y si SE-400 F1 forma parte del schema SAM de SE-397.
2. Decidir autoridad de canonical sources antes de migrar `.claude/.opencode`.
3. Decidir si corregir resolver/rule manifests es prerequisite independiente.
4. Revisar los ocho DELETE históricos; ninguno está confirmado.
5. Mantener todo physical removal, pack migration y hot-path enforcement change
   detrás de su Human Gate.

## Verdict

`GO_WITH_CONCERNS` para normalización read-only. `NO_F1` hasta revisión. La
superficie real es mayor y más heterogénea que las 1.464 entradas SCM; una cifra
única de capabilities semánticas sería actualmente `NOT_VERIFIED`.
