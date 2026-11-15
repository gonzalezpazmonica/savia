# Spec: SE-348 — Auditoría de integridad de Savia + plan de activación

**Status:** APPROVED→PARCIALMENTE IMPLEMENTADO (2026-08-27, aprobación operadora salvo hardware)
**Fecha:** 2026-08-27
**Area:** Integridad / Activación / Soberanía
**Developer Type:** agent-single (activación) + humano (decisiones de descarga)
**Context risk:** low
**Estimación:** auditoría ~2h (hecha) · activación por capas (ver §4)
**Criterio rector:** CRIT-001 — todo local; nada N3+ a proveedor cloud.

---

## 1. Contexto y objetivo

Antes de seguir con el plan unificado, se audita la integridad de Savia: qué
está **funcionando**, qué está **listo pero no activado**, qué está
**pendiente de activar** (requiere software/modelos), y qué **falta vs otros
workspaces** (research GitHub/HF). El objetivo es un mapa honesto del estado
real y un plan de activación priorizado, sin autoengaño (radical-honesty: lo
que no está activo se dice como no activo).

## 2. Resultado de la auditoría (2026-08-27, verificado empíricamente)

### 2.1 FUNCIONANDO (activo, verificado)

| Componente | Evidencia |
|---|---|
| Core PM-workspace | readiness-check: **153 PASS / 0 FAIL / 3 WARN** (node, bats, on-main — opcionales) |
| Hooks → plugin savia-gates | 115 hooks bridged; self-heal + killTree (49 bats plugin) |
| Skills | 129 skills, auditor 0 FAIL (conformidad agentskills.io) |
| Agentes / comandos | 83 agents · 570 commands |
| MCP servers | codebase-memory, codegraph, savia-vaults (procesos activos) |
| Shield daemon (regex gate) | :8444 up (`/gate` ALLOW); capas 1/5/6 activas |
| Memoria | memory-store grep mode operativo; índice MEMORY.md |
| Automatizaciones | scheduler con 6 tareas default |
| Seguridad | gates de commit/confidencialidad/CRIT-001 operativos (verificados en vivo) |
| SE-344 FxC | fronema CLI + cúpula Fronesia + 6 seed (13 bats) |
| SE-338/339/346 | rule-manifest · coverage ratchet (100%) · surrogate `--check` |
| Cúpulas | SaviaLearning, SaviaLabs, savia-docs, SaviaDomains, Fronesia |
| Evals | corpora en `tests/evals/` (anti-sycophancy, court, security, classifier) |

### 2.2 LISTO pero NO ACTIVADO (construido, sin cablear)

| Componente | Estado real | Qué falta para activar |
|---|---|---|
| **SE-346 llm-router** | **Slice 2 cableado 2026-08-27**: `savia_model_by_uncertainty()` en savia-env.sh (advisory) | Dispatch automático completo: futuro |
| **Sandbox opencode-sandbox** | `enabled: false` en opencode.json; bwrap **no instalado** | Instalar bwrap + `enabled: true` |
| **Shield NER** (capa 2) | **ACTIVADO 2026-08-27**: spaCy+Presidio+es_core_news_md en venv, `ner: true`, gate detecta EMAIL/PERSON | Clasificador qwen2.5:7b diferido (hardware) |
| **savia-dual (failover local)** | skill documentado; no verificado que el failover real esté wired | Verificar/activar el trigger en arranque de sesión |
| **FxC gate de consulta** | `fronema.py query` manual; NO hay hook de recordatorio en gates | Hook opcional (fuera de alcance SE-344) |
| **Vector search / embeddings** | **ACTIVADO 2026-08-27**: servidor 7331 up (all-MiniLM-L6-v2) + búsqueda vectorial con scores | — |
| **Memoria auto-consolidation** | SE-264 implementado (MEMORY.md); ejecución periódica no verificada | Confirmar tarea programada |
| **SE-347 PMA** | evaluado (RE-EVALUAR); no runtime | (ver §2.3) |

### 2.3 PENDIENTE DE ACTIVAR (requiere software/modelos)

| Necesidad | Bloquea | Candidato (research) |
|---|---|---|
| **Modelo local ≥8B usable** | Soberanía de inferencia · SE-347 S3 · benchmark · E3 resiliencia · failover savia-dual real | **DIFERIDO (limitación de hardware, operadora 2026-08-27)** — Qwen2.5-7B-Instruct cuando haya hardware |
| **bwrap** | Sandbox | paquete del sistema |
| **qwen2.5:7b + spaCy NER** | Shield capa NER | Ollama pull + modelo spaCy |
| **Modelo de embedding (multilingüe)** | Recall vectorial de calidad | BAAI/bge-m3 (HF) |

### 2.4 FALTA vs otros workspaces (research GitHub/HF, 2026-08-27)

| Capacidad que otros tienen | Estado en Savia | Fuente de investigación |
|---|---|---|
| **Sandbox de ejecución real** (bwrap/Docker) | Configurado pero `enabled:false` (bwrap ausente) | opencode sandbox; SPEC-149 (Docker) implementada pero inactiva |
| **RAG híbrido activo** (embeddings + reranker) | deps listas; servidor off; sin reranker (cross-encoder) | HF: BAAI/bge-m3 + cross-encoders |
| **Modelo local ≥8B en servicio** (vLLM/Ollama) | Ollama con 3b (débil) y 26b (lenta); sin ≥8B usable | HF: Qwen2.5-7B-Instruct |
| **Eval unificado por capa** | corpora existen; runner/score por capa no integrado en CI | DeepEval / lm-eval-harness (ecosistema HF/GitHub) |
| **Validador skills-ref** | conformidad propia; no usa la lib de referencia | agentskills.io / agentskills/agentskills (skills-ref) |
| **Observabilidad OTel** | base SE-313 + SE-534 fingerprint | ya cubierto (no falta) |

> Nota: HF devuelve páginas de modelos como stub en esta sesión; las
> especificaciones de los candidatos (bge-m3, Qwen2.5-7B) se verifican en el
> momento de la descarga (tamaño, licencia, RAM).

## 3. Investigación GitHub/HF (fuentes)

- **agentskills.io/specification** — formato Agent Skills (Savia conforme, 129
  skills). GitHub `agentskills/agentskills` (skills-ref validator).
- **HF candidatos** (local-first, CRIT-001): `BAAI/bge-m3` (embedding
  multilingüe ~560M, sirve para el recall vectorial y el NER del Shield),
  `Qwen/Qwen2.5-7B-Instruct` (modelo local ≥8B de propósito general para la
  soberanía de inferencia; descarga vía Ollama, sin dependencia cloud).
- **Ecosistema**: opencode sandbox (bwrap), Docker sandboxing (SPEC-149),
  DeepEval/lm-eval (evals). Todo ejecutable local.

## 4. Plan de activación (priorizado)

| Prioridad | Capa | Acción | Esfuerzo | Bloquea |
|---|---|---|---|---|
| P0 | Soberanía inferencia | ~~Descargar modelo ≥8B~~ **DIFERIDO (hardware)** | — | E3, benchmark |
| P0 | Sandbox | **BLOQUEADO — requiere sudo (operadora)**: instalar bwrap + `enabled:true` | 15 min | aislamiento ejecución |
| P1 | Vector recall | ~~Arrancar + índice~~ **ACTIVADO** · reranker bge-reranker opcional | — | recall híbrido |
| P1 | Shield NER | ~~spaCy+Presidio~~ **ACTIVADO (capas regex+NER)** · clasificador qwen2.5:7b diferido (hardware) | — | PII detección |
| P2 | Router SE-346 | ~~Slice 2~~ **ACTIVADO** (`savia_model_by_uncertainty`) · dispatch completo futuro | — | ahorro coste |
| P2 | Evals unificados | Runner de evals por capa integrado en CI | 3h | calidad |
| P3 | FxC gate hook | ~~Hook~~ **ACTIVADO** (`fronesis-gate-reminder.sh`, warn-only en pr-create/merge) | — | uso FxC |
| P3 | skills-ref | Validar skills con la lib de referencia | 30 min | conformidad externa |

Todas las acciones locales. Las descargas (modelos) requieren aprobación de la
operadora (autonomous-safety: la IA propone, la operadora dispone; descargas
de modelos = decisión de hardware/red).

## 5. Criterios de aceptación

- AC-1: `readiness-check` sigue 0 FAIL tras activaciones.
- AC-2: sandbox activo (bwrap presente + `enabled:true`) y un comando de
  prueba corre confinado.
- AC-3: Shield `ner:true` y capa 2 activa (health check).
- AC-4: vector recall: embedding server up + índice generado + `memory-store
  search --mode vector` responde (o hnswlib).
- AC-5: savia-dual con modelo local ≥8B: failover real verificado en un test
  de corte de cloud (o documentado como E3).
- AC-6: llm-router cableado en modo `--check`→dispatch opcional (slice 2) o
  explícitamente diferido con evidencia.
- AC-7: spec actualizada al activar cada capa (nada "listo pero no activado"
  queda sin documentar su estado real).

## 6. CRIT-001

Todas las activaciones son locales (bwrap, Ollama local, embeddings locales,
spaCy). Ninguna añade egress de datos N3+. Las descargas de modelos se hacen a
infraestructura propia y se auditan (hash/licencia) antes de usar.

## 7. Referencias

- `scripts/readiness-check.sh` · `opencode.json` · `savia-vaults.domes.json`
- SE-344 (FxC) · SE-346 (surrogate) · SE-347 (PMA) · SE-338/339 · SPEC-149 (sandbox)
- Research: agentskills.io · HF BAAI/bge-m3 · Qwen2.5-7B-Instruct
- CRIT-001 · autonomous-safety.md (la IA propone, la operadora dispone)
