---
layer: peripheral
name: tier3-probes
description: Usar cuando se valida la viabilidad de herramientas Tier 3 antes de adoptarlas en el workspace.
allowed-tools: [Bash, Read]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: architect
  savia.maturity: stable
  savia.category: quality
  savia.context: fork
  savia.disable-model-invocation: false
  savia.maturity: stable
  savia.priority: low
  savia.summary: "Aggregator skill listando 6 probes Slice 1 de champions Tier 3. Cada probe verifica preconditions (Python version, pip deps, disk, browser opcional) antes de adoptar stack. Zero-egress, exit codes estables (0/1/2)."
  savia.tags: "probes, viability, tier3, dependencies, feasibility"
  savia.user-invocable: True
---

# Skill: Tier 3 Probes

> Feasibility probes antes de instalar dependencias pesadas.
> Ref: Era 183 Tier 3 Champions.

## Cuando usar

- Antes de `pip install` pesado para un champion Tier 3
- Verificar entorno tras travel-pack a maquina nueva
- Auditoria periodica de preconditions ML stack
- Pre-activacion de MCP templates (scrapling opt-in)

## Inventario

| Probe | Champion | Spec | Verifica |
|---|---|---|---|
| `scrapling-probe.sh` | Scrapling | SE-061 | Python >= 3.10, scrapling, lxml, opcional playwright+chromium |
| `oumi-probe.sh` | Oumi training | SE-028 | Python 3.10+, oumi, torch, disk >= 10GB |
| `memvid-probe.sh` | Memvid backup | SE-041 | Python 3.10+, memvid |
| `bertopic-probe.sh` | BERTopic | SE-033 | Python, bertopic, sentence-transformers, UMAP, HDBSCAN |
| `reranker-probe.sh` | Cross-encoder | SE-032 | Python, sentence-transformers, torch, BAAI model availability |
| `pdf-extract-probe.sh` | PDF chain | SPEC-102/103/104 | Python, pdfminer, java deps |

## Invocacion uniforme

Todos los probes siguen el mismo contrato:

```bash
bash scripts/X-probe.sh            # Verbose output
bash scripts/X-probe.sh --json     # Machine-readable
```

### Output schema (JSON)

```json
{
  "verdict": "VIABLE|NEEDS_INSTALL|BLOCKED",
  "python_version": "3.12.3",
  "{package}_installed": 0|1,
  "disk_free_gb": 100,
  "reasons": ["human-readable explanation"]
}
```

### Exit codes

- `0` — VIABLE o NEEDS_INSTALL (no bloqueador)
- `1` — BLOCKED (Python incompatible, disk insuficiente, dep critica ausente)
- `2` — usage error (flag desconocido)

## Casos de uso

### Pre-install check
```bash
bash scripts/scrapling-probe.sh --json | jq .verdict
# → "VIABLE" → proceder con `pip install scrapling`
```

### Batch check environment readiness
```bash
for p in scrapling oumi memvid bertopic reranker pdf-extract; do
  echo "=== $p ==="
  bash scripts/$p-probe.sh --json | jq .verdict
done
```

### CI gate (opcional)
Un PR que añade champion Tier 3 puede verificar que el probe devuelve VIABLE|NEEDS_INSTALL antes de merge.

## No hacen

- No instalan dependencias (solo verifican)
- No descargan modelos
- No ejecutan inference (eso es Slice 2+ de cada champion)
- No auto-fixer (requiere intervención humana)

## Patron de diseno (SE-061 reference)

Cada probe:
1. Verifica herramientas nativas (python3, pip3, df)
2. Detecta deps Python via `python3 -c "import X" 2>/dev/null`
3. Mide disk free
4. Clasifica verdict por 3 categorias
5. Lista reasons humanas para cada fallo
6. JSON estable para automatizacion

Replicar este patron para nuevos Slice 1 de champions futuros.

## Referencias

- SE-061 Scrapling: `docs/propuestas/SE-061-scrapling-research-backend.md`
- SE-032 Reranker: `docs/propuestas/SE-032-reranker-layer.md`
- SE-033 BERTopic: `docs/propuestas/SE-033-topic-cluster-skill.md`
- SE-041 Memvid: `docs/propuestas/SE-041-memvid-portable-memory.md`
- SE-028 Oumi: `docs/propuestas/SE-028-oumi-training-pipeline.md` (diferido)
- Roadmap Era 183: `docs/ROADMAP.md` §Tier 3 Champions
