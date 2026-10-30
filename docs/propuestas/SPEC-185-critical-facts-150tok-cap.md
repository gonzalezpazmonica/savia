---
spec_id: SPEC-185
title: Critical-facts 150-token cap (anchor superior persistente)
status: IMPLEMENTED
tier: 1
priority: P2
effort: 1-2h
era: 199
wave: 1
deps: []
unblocks: []
origin: output/research/obsidian-second-brain-mejoras-cupulas-20260601.md
inspiration: obsidian-second-brain `critical-facts.md` (anclaje superior <150 tokens, leido siempre)
timeline:
  - from: "2026-06-01"
    until: "2026-06-05"
    learned: "2026-06-01"
    value: "PROPOSED"
    source: "feat(roadmap): Era 199 -- 7 SPECs from obsidian-second-brain analysis (#794)"
  - from: "2026-06-05"
    learned: "2026-06-05"
    value: "IMPLEMENTED"
    source: "feat(spec-157): Context Pre-Flight Check multi-source token estimator (#814)"
---

# SPEC-185 — Critical-facts 150-token cap

> Estado: PROPOSED · Tier 1 · P2 · Estimacion 1-2h · Era 199 · Wave 1

## Resumen

Crear `docs/critical-facts.md` con hard-cap de 150 tokens, cargado en cada turno como anchor superior. Contiene SOLO hechos invariantes del workspace (idioma activo, sprint actual, gates inmutables). Validador rechaza commits que excedan el cap.

## Motivacion

- CLAUDE.md (4 imports lazy) carga ~3K tokens fijos por turno.
- Hay 6-8 hechos verdaderamente criticos (idioma, sprint, persona activa) que necesitan estar SIEMPRE arriba para evitar context-rot en sesiones largas.
- Patron obsidian: anchor de <150 tokens al inicio garantiza que el modelo nunca pierde los invariantes.

## Scope

1. Crear `docs/critical-facts.md` con seccion delimitada por marcadores `<!-- CRITICAL_FACTS_START -->` / `<!-- CRITICAL_FACTS_END -->`.
2. Hard-cap 150 tokens medido con `tiktoken` o aproximacion `wc -w * 1.3`.
3. Auto-generacion por hook PreCommit que extrae: idioma activo, sprint actual, persona activa, gates inmutables (Rules 1-3, 8, 25).
4. CLAUDE.md anade `@docs/critical-facts.md` como 5o import lazy (primer slot).
5. Validador `scripts/validate-critical-facts-cap.sh` exit 1 si excede 150 tokens.
6. Documentar en `docs/rules/domain/critical-facts-anchor.md` la politica.

## Acceptance Criteria

- AC1: `docs/critical-facts.md` existe con marcadores correctos.
- AC2: Validador rechaza fichero >150 tokens (test con fixture de 200 tokens falla, fixture de 140 tokens pasa).
- AC3: CLAUDE.md carga `@docs/critical-facts.md` como primer import.
- AC4: Auto-generacion del hook produce contenido determinista (mismo input -> mismo output).
- AC5: BATS verifica que los 6 campos canonicos (idioma, identidad, persona, 3 gates) aparecen. (2026-10-30, SE-483: el campo `Sprint` pasa a `Identidad` con la frase corta de `.claude/profiles/savia.md`.)
- AC6: Hook PreCommit anade fichero al stage si el contenido cambio.
- AC7: Si el fichero excede el cap, hook PreCommit sugiere que campos eliminar por relevancia.
- Enmienda SE-487 (2026-10-30): el fichero es versionado y público, así que no lleva idioma, slug, nombre ni fecha de activación de ninguna persona. El campo «Persona activa» remite al arranque (`session-init.sh`), que inyecta la identidad desde el perfil local gitignored; sin perfil dice «Sin perfil: no sé quién eres». El generador no lee el perfil ni las preferencias locales.

## Slices

1. **Slice 1 (0.5h)** — Crear fichero + marcadores + validador shell.
2. **Slice 2 (0.5h)** — Hook PreCommit auto-generador.
3. **Slice 3 (0.5-1h)** — Registrar import en CLAUDE.md + BATS tests + doc.

## Out of scope

- Anchor dinamico por proyecto (v1 solo workspace global).
- Inyeccion en system prompt (eso lo hace cada frontend via su mecanismo de imports).
- Soporte multi-idioma para los facts (v1 espanol fijo).
