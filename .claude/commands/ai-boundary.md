---
name: ai-boundary
description: "Definir matriz de límites explícitos: qué puede hacer Savia autónomamente vs requiere aprobación"
developer_type: all
agent: none
context_cost: low
tier: extended
---

# /ai-boundary

> 🦉 Delimitar es responsabilidad. Savia trabaja mejor con límites claros.

Definir una matriz de límites por rol: acciones autónomas vs acciones que requieren aprobación.

---

## Matriz de Límites (Ejemplos por Rol)

### Developer

- **Crear PBI**: ≤ 3 pts autónomo | > 3 pts requiere aprobación
- **Asignar trabajo**: propia capacidad | otro dev requiere aprobación
- **Crear rama**: feature/fix branch | main/develop requiere aprobación
- **Push a código**: feature branch | release/main requiere aprobación

### PM / Scrum Master

- **Crear PBI**: siempre autónomo
- **Cambiar prioridad**: < 10 movimientos | > 10 requiere aprobación
- **Generar informe**: histórico | proyecciones futuro requiere aprobación
- **Cambiar config sprint**: requiere aprobación siempre

### Tech Lead

- **Crear spec**: siempre autónomo
- **Cambiar estándares código**: requiere aprobación (team-wide)
- **Spec infra DEV/PRE**: autónomo | PRO requiere aprobación
- **Refactor módulo aislado**: autónomo | crítico requiere aprobación

---

## Flujo

1. **Paso 1** — Leer `identity.md` para determinar rol del usuario
2. **Paso 2** — Presentar matriz interactiva del rol
3. **Paso 3** — Permitir personalización de límites (opcional)
4. **Paso 4** — Guardar en `company/policies.md` con validación de coherencia
5. **Paso 5** — Aplicar límites a futuras acciones

---

## Validación Automática

Cuando Savia va a ejecutar una acción:
```
Acción: crear PBI "Feature X"
Estimación: 8 pts
Rol: Developer
Límite: ≤ 3 pts

⚠️ Límite excedido (8 > 3)
   Savia propone pero NO ejecuta automáticamente.
```

---

## Restricciones

- **NUNCA** ignorar límites una vez definidos
- **NUNCA** permitir nivel más permisivo para Delete que para Create
- **NUNCA** producción menos restrictiva que desarrollo
- Validar coherencia: si Create requiere aprobación, Update también
- Umbrales deben ser números enteros positivos

---

## Integración

- `/ai-safety-config` — niveles de supervisión (inform/recommend/decide/execute)
- `/ai-confidence` — qué requiere validación
- `/ai-incident` — monitorizar cumplimiento de límites

Ver `@docs/rules/domain/pm-config.md` para config completa.