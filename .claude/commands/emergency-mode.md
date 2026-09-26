---
name: emergency-mode
description: Gestionar el modo emergencia con LLM local cuando el proveedor cloud no está disponible
developer_type: all
agent: none
context_cost: low
model_tier: fast
tier: core
---

# /emergency-mode {subcommand}

> Gestiona el modo emergencia de PM-Workspace para operar con un LLM local.

---

## Prerequisitos

- Linux/macOS: terminal con bash · Windows: PowerShell (usar scripts `.ps1`)
- Para `setup`: conexión a internet (o caché de emergency-plan para offline)
- Para `activate/status/test`: Ollama instalado previamente

## Subcomandos

### `/emergency-mode setup`

Ejecuta el script de configuración inicial:

1. Detecta hardware (SO, RAM, GPU)
2. Instala Ollama si no está presente
3. Descarga modelo recomendado según RAM disponible
4. Configura variables de entorno
5. Verifica conectividad

Equivale a: `./scripts/emergency-setup.sh`

Modelos por hardware:
- 8GB RAM: `qwen2.5:3b`
- 16GB RAM: `qwen2.5:7b` (default)
- 32GB+: `qwen2.5:14b`

### `/emergency-mode status`

Muestra diagnóstico completo:
- ¿Ollama instalado? ¿Servidor activo?
- Modelos disponibles con tamaño
- Variables de entorno configuradas
- RAM y GPU disponible
- Problemas detectados con sugerencias

Equivale a: `./scripts/emergency-status.sh`

### `/emergency-mode activate`

Activa el modo emergencia:

1. Verifica que Ollama está instalado y servidor activo
2. Si no hay servidor → intenta iniciarlo (`ollama serve`)
3. Configura `ANTHROPIC_BASE_URL=http://localhost:11434`
4. Configura `PM_EMERGENCY_MODE=active`
5. Ejecuta test básico de conectividad

Resultado: Claude Code usará el LLM local en lugar del cloud.

**Variables de modelo configuradas** (oficiales de Claude Code):
- `ANTHROPIC_DEFAULT_OPUS_MODEL` → modelo local grande (según RAM)
- `ANTHROPIC_DEFAULT_SONNET_MODEL` → modelo local medio
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` → modelo local pequeño (qwen2.5:3b)
- `CLAUDE_CODE_SUBAGENT_MODEL` → modelo para subagentes

Los 27 agentes que especifican `model: opus/sonnet/haiku` resolverán a modelos locales.

**Limitaciones en modo emergencia**:
- Velocidad: más lento que Opus/Sonnet en cloud
- Capacidad: modelos 7B son ~60-80% de la calidad de Sonnet
- Contexto: 8K-32K tokens (vs 200K+ en cloud)
- Agentes: funcionan pero con calidad reducida

### `/emergency-mode deactivate`

Restaura la configuración original:

1. Elimina `ANTHROPIC_BASE_URL` override
2. Desactiva `PM_EMERGENCY_MODE`
3. Opcionalmente detiene el servidor Ollama

### `/emergency-mode test`

Ejecuta un prompt simple para verificar que el LLM local responde:

1. Envía prompt de test al endpoint local
2. Mide tiempo de respuesta
3. Reporta: modelo, latencia, estado

## Operaciones sin LLM

Si el LLM local tampoco funciona, usar:

```bash
./scripts/emergency-fallback.sh git-summary       # Resumen git
./scripts/emergency-fallback.sh board-snapshot     # Estado del board
./scripts/emergency-fallback.sh team-checklist     # Checklists Scrum
./scripts/emergency-fallback.sh pr-list            # PRs pendientes
./scripts/emergency-fallback.sh branch-status      # Ramas activas
```

## Documentación completa

Ver `docs/EMERGENCY.md` (español) o `docs/EMERGENCY.en.md` (inglés).
