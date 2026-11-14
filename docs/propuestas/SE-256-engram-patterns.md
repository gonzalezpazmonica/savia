# SE-256 — Patrones de engram aplicados a Savia

**Origen:** analisis de engram v1.16.3→v1.18.0 (Gentleman-Programming/engram)
**Relacion:** extiende SE-255 (constitucion, libro de relacion, lealtad)
**Branch:** agent/se256-engram-patterns
**Estimacion:** 3h
**Estado (2026-11-13):** IMPLEMENTED parcial. S1 ARCHIVED, S2 ARCHIVED, S3 implementado sin invocador.

| Slice | Estado | Motivo |
|---|---|---|
| S1 save-nudge | ARCHIVED | Nunca se registro como hook; `memory-auto-capture` ya captura por ediciones. Script y tests retirados. |
| S2 deteccion de conflictos | ARCHIVED | Lee `data/relacion/ledger.jsonl`, que ningun flujo escribe (`relacion-capture.sh` solo lo llaman sus tests). Sin consumidor. |
| S3 verify-principal | IMPLEMENTED, sin invocador | CRITERIO CRIT-031 lo cita como enforcement y `config/hook-thresholds.yaml` lo lista como no modulable, pero ningun hook ni flujo lo ejecuta, y su comprobacion solo cuenta ficheros de sesion. Decision pendiente: cablearlo con una comprobacion real o corregir CRIT-031. No se toca aqui. |

Los AC de S1 y S2 de abajo quedan como historicos: no se cumplen y no se van a cumplir.

---

## Slice 1 — Save-nudge: captura automatica periodica

**Problema:** el libro de la relacion (SE-255 S3) solo captura eventos via CLI manual.
El agente olvida registrar overrides, decisiones y errores en sesiones largas.

**Aprendizaje de engram:** el plugin de OpenCode recuerda cada 15 minutos guardar
memorias con un nudge no-intrusivo. Debounce evita spam.

**Diseno:** hook PostToolUse que cada 15 minutos recuerda "¿algo que registrar
en el libro de la relacion?" si se detectaron overrides/edit/revert no capturados.
Debounce: solo emite si realmente hubo acciones dignas de registro desde el
ultimo nudge.

**AC:**
- AC-1.1: Nudge aparece cada ~15 min si hubo overrides/edit/revert no registrados
- AC-1.2: Debounce: no emite mas de 1 nudge por ventana de 15 min aunque haya 50 eventos
- AC-1.3: Nudge NO bloquea ni interrumpe el flujo (PostToolUse, exit 0 siempre)
- AC-1.4: Si no hubo eventos capturables desde ultimo nudge, no emite nada

---

## Slice 2 — Deteccion de conflictos en el ledger

**Problema:** el ledger registra entradas atomicas pero no detecta cuando una
entrada contradice a otra (ej: "usar Postgres" → override → "usar MongoDB").
Sin deteccion de conflicto, la relacion no tiene memoria de sus propias
contradicciones.

**Aprendizaje de engram:** FTS5 detecta candidatos lexicos (titulos compartidos),
luego LLM juzga semantica (supersedes/conflicts_with). $0 marginal si el
usuario ya tiene subscripcion.

**Diseno:** `scripts/relacion-detect-conflicts.sh` que:
1. Lee el ledger
2. Busca pares de entradas con ambitos/topicos solapados pero decisiones opuestas
3. Marca relaciones (supersedes/conflicts_with/refines)
4. Propone resolucion en el siguiente brief

**AC:**
- AC-2.1: Detecta pares contradictorios en el ledger (mismo ambito, distinta decision)
- AC-2.2: Clasifica como supersedes (cronologico) o conflicts_with (misma ventana)
- AC-2.3: Reporta en formato JSON parseable
- AC-2.4: No modifica el ledger, solo lee y reporta

---

## Slice 3 — Verificacion de principal unico (ART-16)

**Problema:** ART-16 declara "la operadora es el principal unico" pero no hay
mecanismo que verifique que las instrucciones realmente provienen de ella.
Prompt injection, sesiones no autenticadas y terceros intercalados son
teoricamente detectables pero no se verifican activamente.

**Aprendizaje de engram:** token-pepper con hashing para managed auth: el token
se muestra una sola vez, se almacena hasheado, y se verifica contra el pepper
en runtime. deny-by-default para proyectos sin grant.

**Diseno:** `scripts/verify-principal.sh` que:
1. Verifica que la sesion actual corresponde al principal declarado
2. Comprueba firma de sesion contra registro de sesiones autorizadas
3. Si detecta origen no reconocido → entrada en ledger + alerta

**AC:**
- AC-3.1: Verifica que el directorio de sesion tiene firma reconocible
- AC-3.2: Sesion sin firma → WARN + entrada en ledger (no bloquea)
- AC-3.3: Script funciona sin dependencias cloud
