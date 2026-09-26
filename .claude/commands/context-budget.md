---
name: context-budget
description: Presupuesto de contexto por sesión — tokens usados/disponibles, distribución por capa, sugerencias de optimización
developer_type: all
agent: task
context_cost: high
model_tier: fast
tier: core
---

# Comando: context-budget

## Sinopsis

Mostrar el presupuesto de contexto consumido en la sesión actual y disponible. Analizar distribución por capa (system, rules, commands, conversation, tools). Identificar mayores consumidores de tokens. Sugerir optimizaciones para reducir consumo.

## Sintaxis

```bash
/context-budget [--show] [--optimize] [--lang es|en]
```

Flags:
- `--show` — mostrar desglose actual de tokens por capa (por defecto si no hay otro flag)
- `--optimize` — ejecutar análisis de optimización y sugerir recortes
- `--lang es|en` — idioma del output (español/inglés)

## Comportamiento

### 1. Cargar perfil de usuario (si está activo)

Leer `.claude/profiles/active-user.md` → obtener `active_slug`.
Si hay perfil activo, cargar fragmentos según context-map (preferencia PBI).

### 2. Mostrar presupuesto actual (con `--show`)

Banner con:
- **Budget total**: ~160k tokens (límite Claude)
- **Usados sesión actual**: X tokens (sistema + reglas + comandos cargados + conversación)
- **Disponibles restantes**: Y tokens
- **Porcentaje usado**: X / 160k (%)

Desglose por capa (tabla):

| Capa | Tokens | % | Ejemplos |
|---|---|---|---|
| System | 800 | 0.5% | Instrucciones Claude |
| Rules | 2500 | 1.6% | docs/rules/ cargadas |
| Commands | 1200 | 0.8% | .opencode/commands/ referenciadas |
| Conversation | 45000 | 28% | Mensajes usuario/Claude |
| Tools | 900 | 0.6% | MCPs e integraciones |
| **Total** | **50400** | **31.5%** | — |

### 3. Ejecutar análisis de optimización (con `--optimize`)

Tres análisis secuenciales:

**3a. Top consumidores**
```
🔴 Mayores consumidores:
  1. conversation (45KB) — 45% del total
  2. system rules (2.5KB) — 5%
  3. context-map cargado (1.2KB) — 2%
```

**3b. Detección de cargo innecesario**
```
⚠️ Cargos detectados sin referencia en outputs recientes:
  - rule: backup-protocol.md (0 referencias en últimas 10 mensajes)
  - skill: legacy-capture.md (0 referencias)
  → Candidatos a descargar
```

**3c. Recomendaciones de recorte**
```
💡 Recomendaciones:
  1. Ejecuta /compact para resetear conversación (recuperarías ~40KB)
  2. Descargar regla: /rule unload backup-protocol
  3. Usar @context-defer para cargar rules bajo demanda
  4. Resumir decision-log en archivos antiguos: /context-age apply
```

## Output

### Si `--show` (o sin flags)

Tabla formateada en Markdown + banner de presupuesto.

### Si `--optimize`

Análisis completo + tabla top 5 consumidores + 3-5 recomendaciones concretas.

## Notas

- **Frecuencia sugerida**: ejecutar cada 5-10 comandos si contexto se siente "pesado"
- **Auto-call**: Savia puede sugerir `/context-budget --optimize` si detecta uso > 75%
- **Post-comando**: Banner de finalización incluye: "⚡ /compact — ejecuta para liberar contexto"

## Integración

Conecta con:
- `/context-defer` — cargar rules bajo demanda
- `/context-profile` — análisis profundo por rol/comando
- `/context-compress` — compresión semántica
- `/compact` — resetear contexto sin perder estado

