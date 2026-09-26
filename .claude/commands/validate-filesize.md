---
name: validate-filesize
description: Validar que ficheros del workspace cumplen ≤150 líneas
agent: commit-guardian
model_tier: fast
context_cost: low
tier: core
---

# /validate-filesize

Verifica que todos los ficheros gestionados del workspace (skills, agents, rules, commands) cumplen la regla de ≤150 líneas.

---

## Flujo

### 1. Banner inicio

```
╔══════════════════════════════════════╗
║  📏 Validate File Size              ║
╚══════════════════════════════════════╝
```

### 2. Escanear ficheros

Categorías a revisar:
- `.opencode/skills/*/SKILL.md`
- `.opencode/agents/*.md`
- `docs/rules/domain/*.md`
- `.opencode/commands/*.md`
- `scripts/*.sh`
- `CLAUDE.md`

### 3. Validar

Para cada fichero:
```bash
lines=$(wc -l < "$file")
if [ "$lines" -gt 150 ]; then
    echo "❌ FAIL: $file ($lines líneas)"
fi
```

### 4. Resumen

```
📊 Resultado: X ficheros revisados, Y ok, Z exceden 150 líneas
```

Excepciones conocidas (legacy): ficheros en `rules/languages/` pueden exceder.

### 5. Banner fin

```
╔══════════════════════════════════════╗
║  ✅ File Size Validation — Completo ║
╚══════════════════════════════════════╝
⚡ /compact
```
