---
layer: peripheral
name: memvid-backup
description: Usar cuando se crea un backup portable de la memoria externa de Savia.
allowed-tools: [Read, Bash, Write]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: memory
  savia.context: fork
  savia.disable-model-invocation: false
  savia.maturity: experimental
  savia.priority: low
  savia.summary: "Wrapper backup para memoria externa. Intenta memvid (.mv2) si disponible, fallback a tar-gzip con SHA256 integrity. 3 subcomandos: pack, restore, verify. Integrable con travel-pack / vault-export."
  savia.tags: "backup, memvid, portable, travel, integrity"
  savia.user-invocable: True
---

# Skill: Memvid Backup

> Evalua memvid como formato portable para memoria externa.
> Ref: SE-041, docs/propuestas/SE-041-memvid-portable-memory.md.

## Cuando usar

- Backup de `.claude/external-memory/` antes de cambios estructurales
- Travel-pack para llevar memoria a otra maquina
- Verificar integridad de un backup antes de restaurar
- Experimentar con formato memvid vs tar-gzip

## Cuando NO usar

- Backup de repos git (usa git)
- Backup de datos de produccion criticos (hay herramientas dedicadas)
- Snapshots frecuentes (<1h) — overhead innecesario

## Subcomandos

### pack

Empaqueta un directorio a fichero portable:

```bash
python3 scripts/memvid-backup.py pack \
  --src ~/.claude/external-memory/auto \
  --out /tmp/memory-backup-$(date +%Y%m%d).tar.gz \
  --json
```

Output: `format`, `size_bytes`, `sha256`, `latency_ms`.

### restore

Restaura un backup a directorio:

```bash
python3 scripts/memvid-backup.py restore \
  --src /tmp/memory-backup-20260422.tar.gz \
  --out /tmp/memory-restored \
  --json
```

Output: `format`, `files_extracted`, `latency_ms`.

### verify

Verifica integridad (sin extraer):

```bash
python3 scripts/memvid-backup.py verify \
  --src /tmp/memory-backup-20260422.tar.gz \
  --json
```

Output: `format`, `size_bytes`, `sha256`, `members`.

## Formato automatico

Con `--format auto` (default en pack):
- Si `memvid` instalado → intenta .mv2 (fallback si falla)
- Si no instalado → tar-gzip con SHA256

Forzar formato: `--format tar-gzip` o `--format memvid`.

## Integracion con travel-pack

Para uso en travel-pack workflow:

```bash
# Pre-travel: backup local
python3 scripts/memvid-backup.py pack --src ~/.claude/external-memory --out $USB/memory.tar.gz

# Post-travel: restore en nueva maquina
python3 scripts/memvid-backup.py verify --src $USB/memory.tar.gz
python3 scripts/memvid-backup.py restore --src $USB/memory.tar.gz --out ~/.claude/external-memory
```

## Criterios acceptance SE-041

- [ ] Pack 100 engrams reales < 30s → pendiente eval real
- [ ] Round-trip byte-identical → SHA256 check implementado
- [ ] Portabilidad single-file → tar-gzip cumple, memvid .mv2 pendiente

## Instalacion (opcional)

```bash
pip install memvid  # ~15k stars, Apache 2.0
```

Zero-install default: tar-gzip siempre funciona.

## Costes

- Sin deps: 0 MB extra, tar-gzip nativo
- Con memvid: ~200MB (incluye BGE-small ONNX 384d)
- Egress: solo si memvid descarga modelo ONNX

## Referencias

- Spec: `docs/propuestas/SE-041-memvid-portable-memory.md`
- Script: `scripts/memvid-backup.py`
- Probe: `scripts/memvid-probe.sh`
- Tests: `tests/test-memvid-backup.bats`
