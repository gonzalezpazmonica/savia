---
name: memory-context
description: >
  Muestra las últimas observaciones de memoria para el proyecto activo. Útil al inicio de sesión o tras /compact.
model_tier: fast
context_cost: low
tier: core
---

# ⚡ Contexto de Memoria

Muestra las observaciones recientes almacenadas en memoria persistente para el proyecto activo.

## Uso

```
/memory-context [--limit N]
```

### Parámetros

- **--limit N** (opcional): Número máximo de items a mostrar (default: 10)

## Proceso

**1. Cargar perfil de usuario**

1. Leer `.claude/profiles/active-user.md` → obtener `active_slug`
2. Si hay perfil activo, cargar (grupo **Memory** del context-map):
   - `profiles/users/{slug}/identity.md`
3. Usar slug para aislar memorias por usuario
4. Si no hay perfil → continuar con comportamiento por defecto

**2. Inicio**
```
═══════════════════════════════════════════════════════════
📚 CONTEXTO DE MEMORIA DEL PROYECTO
═══════════════════════════════════════════════════════════
```

**3. Detección de proyecto**
Leo `CLAUDE.local.md` para obtener el proyecto activo.

**4. Recuperación**
```bash
bash scripts/memory-store.sh context \
  [--project {proyecto_activo}] \
  [--limit {N}]
```

**5. Agrupación y formato**
Organizo resultados por tipo:
- **🎯 Decisiones**: Decisiones arquitectónicas o técnicas
- **🐛 Bugs**: Problemas encontrados y soluciones
- **⚡ Patrones**: Patrones de código y mejores prácticas
- **📋 Convenciones**: Estándares del proyecto
- **💡 Descubrimientos**: Hallazgos y aprendizajes

Cada entry muestra:
- Timestamp
- Título
- Resumen del contenido
- Topic key (si aplica)

**5. Fin**
```
═══════════════════════════════════════════════════════════
✅ Contexto cargado
⚡ Usa /memory-search para búsquedas específicas
═══════════════════════════════════════════════════════════
```

## Ejemplos

```
/memory-context

/memory-context --limit 5

/memory-context --limit 20
```

## Casos de uso

- **Inicio de sesión**: Recuperar contexto del proyecto
- **Tras /compact**: Refrescar memoria después de compactar
- **Continuidad**: Mantener coherencia entre sesiones
- **Onboarding**: Aprender decisiones previas

## Restricciones

- ✓ Solo lectura
- ✗ No modifica memoria
- ✗ No ejecuta comandos
