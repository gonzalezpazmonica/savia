---
layer: peripheral
name: savia-memory
description: "Usar cuando se lee, escribe, busca o consolida la memoria persistente entre sesiones de Savia."
license: MIT
compatibility: opencode
metadata:
  audience: pm
  savia.maturity: stable
  workflow: memory-management
  # --- metadata.savia.* (SE-333) ---
  savia.consumes: session_data
  savia.produces: memory_entry
  savia.trigger_keywords: "recuerda, memory, guarda, memoriza, olvidas, recall"
---

# Skill: savia-memory

Gestión de la memoria canónica externa del pm-workspace (`.savia-memory/`).

## Estructura

```
~/.savia-memory/
├── auto/          memoria auto (user/feedback/project/reference)
├── sessions/      snapshots de sesión
├── projects/      memoria por proyecto PM
├── agents/        memoria de agentes (public/private/projects)
├── shield-maps/   mapas mask/unmask Shield
├── pm-radar/      state.json del radar PM
└── jsonl-archive/ archivos JSONL de memoria
```

## Cuándo usar esta skill

- Al inicio de cada sesión: leer `~/.savia-memory/auto/MEMORY.md`
- Para guardar decisiones o aprendizajes: usar `scripts/memory-store.sh`
- Para buscar memoria previa: `scripts/memory-store.sh search <query>`
- Para buscar (alias corto): `scripts/memory-store.sh recall <query>`
- Para ver estadísticas: `scripts/memory-store.sh stats`
- Para consolidar memoria al final de sesión

## Comandos

```bash
# Guardar una entrada en memoria
bash ~/claude/scripts/memory-store.sh save "<tipo>" "<contenido>"

# Buscar en memoria (search o recall)
bash ~/claude/scripts/memory-store.sh search "<query>"
bash ~/claude/scripts/memory-store.sh recall "<query>"

# Ver estadísticas de memoria
bash ~/claude/scripts/memory-store.sh stats

# Reconstruir índice desde JSONL
bash ~/claude/scripts/memory-index-rebuild.sh

# Validar una entrada antes de guardarla (no escribe)
bash scripts/memory-write-gate.sh --content "<contenido>" --type decision \
  --topic-key "<tema>" --confidence 0.8 --concepts '["<concepto>"]'

# Sincronizar markdown de auto-memory al índice (escritura explícita)
bash scripts/memory-sync-index.sh "<directorio-auto-memory>"

# Proponer resolución de conflictos (informe, no modifica el store)
python3 scripts/memory-conflict-resolve.py --store output/.memory-store.jsonl \
  --output output/memory-conflicts-proposed.json

# Consultar estado del backup cifrado (no crea ni restaura backups)
bash scripts/memory-backup-pm.sh status
```

`backup`, `restore`, `--auto-resolve` y la sincronización del índice son
operaciones explícitas. No ejecutarlas automáticamente ni añadirlas a hooks o CI.
`restore` requiere además confirmación humana interactiva.

## Lectura de contexto al inicio

1. Leer `~/.savia-memory/auto/MEMORY.md` — índice de memoria auto
2. Si hay perfil activo en `.claude/profiles/active-user.md`, leer preferencias y contexto
3. Cargar decisiones previas relevantes al proyecto actual

## Protocolo Lazy

- NO cargar toda la memoria al inicio. Solo el índice (`auto/MEMORY.md`).
- Cargar entradas específicas bajo demanda según el contexto de la tarea.
- Usar `search` (o `recall`) para búsqueda semántica cuando necesites contexto relacionado.

## Escritura de memoria

Usar `scripts/memory-store.sh save` con el formato:
```
<tipo>: <descripción>
<contenido>
```

Tipos: decision, pattern, context, feedback, lesson, reference

## Anti-patterns

**❌ Guardar sin tipo**: usar `--type custom` para todo en lugar del tipo semántico correcto (`decision`, `discovery`, `bug`, etc.) → memoria no recuperable por topic, búsquedas devuelven ruido.
**✓ Correcto**: seleccionar el tipo que mejor describe la naturaleza del dato antes de guardar.

**❌ Guardar sin source**: omitir `--source skill:<name>` o `--source session` → trazabilidad rota, entries huérfanas sin origen verificable.
**✓ Correcto**: siempre incluir `--source` con el skill, comando o sesión que originó la entrada.
**❌ Bulk-dump**: guardar todo indiscriminadamente al final de la sesión → memoria saturada con ruido, las entradas valiosas quedan enterradas.
**✓ Correcto**: guardar sólo los datos que tienen valor de recuperación real (decisiones, patrones, bugs con causa-raíz).

**❌ No-recall**: guardar sin consultar nunca la memoria previa → la memoria crece pero no se usa, el agente repite los mismos errores sesión tras sesión.
**✓ Correcto**: al inicio de cada sesión relevante, hacer recall del contexto anterior antes de proponer soluciones.

**❌ Stale-reads**: usar entradas antiguas de memoria sin verificar frescura → decisiones basadas en contexto obsoleto, especialmente peligroso para rutas de ficheros y versiones.
**✓ Correcto**: para entradas con fecha anterior a 30 días, verificar que siguen siendo válidas antes de actuar sobre ellas.
