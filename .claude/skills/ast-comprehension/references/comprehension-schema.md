# Comprehension Report Schema — AST Comprehension

> Schema objetivo. `scripts/ast-comprehend.sh` emite hoy un subconjunto:
> `meta{file,language,lines,tool}`, `structure{classes[{name,line,methods?}],functions[{name,line}],imports,error?}`,
> `complexity{total_decision_points,hotspots[{warn,total}]}` y `summary`. `error` vale `unreadable`
> o `extraction failed` (exit 3) o el mensaje de `SyntaxError` de python-ast (exit 0). Sin `end_line`, modificadores,
> tipos ni `analyzed_at`.

## Schema JSON Completo

```json
{
  "meta": {
    "file": "src/Services/AuthService.cs",
    "language": "csharp",
    "lines": 250,
    "analyzed_at": "2026-03-29T10:00:00Z",
    "tool": "roslyn | tree-sitter | grep-structural",
    "extraction_layers": ["tree-sitter", "roslyn"]
  },
  "structure": {
    "classes": [
      {
        "name": "AuthService",
        "line": 12,
        "end_line": 248,
        "modifiers": ["public"],
        "base_class": "IAuthService",
        "methods": [
          {
            "name": "ValidateToken",
            "line": 45,
            "end_line": 78,
            "modifiers": ["public", "async"],
            "return_type": "Task<bool>",
            "params": ["string token"],
            "complexity": 8
          }
        ],
        "properties": [
          {
            "name": "TokenExpiry",
            "line": 25,
            "type": "TimeSpan",
            "modifiers": ["public", "static"]
          }
        ]
      }
    ],
    "functions": [
      {
        "name": "ParseJwt",
        "line": 300,
        "end_line": 340,
        "modifiers": ["private", "static"],
        "complexity": 5
      }
    ],
    "constants": [
      {
        "name": "MAX_RETRY",
        "line": 8,
        "value": "3",
        "type": "int"
      }
    ],
    "enums": [
      {
        "name": "TokenStatus",
        "line": 400,
        "values": ["Valid", "Expired", "Invalid"]
      }
    ]
  },
  "imports": {
    "internal": ["Services.Core", "Domain.Auth"],
    "external": ["Microsoft.IdentityModel.Tokens", "System.Security.Claims"],
    "standard": ["System", "System.Threading.Tasks"]
  },
  "complexity": {
    "total_decision_points": 42,
    "average_per_function": 5.3,
    "max_function": "ValidateToken",
    "max_value": 8,
    "hotspots": [
      {
        "name": "ValidateToken",
        "line": 45,
        "complexity": 8,
        "warning": false
      },
      {
        "name": "RefreshSession",
        "line": 120,
        "complexity": 14,
        "warning": true
      }
    ]
  },
  "api_surface": {
    "public": ["ValidateToken", "RefreshSession", "RevokeToken", "TokenExpiry"],
    "protected": [],
    "private": ["ParseJwt", "_cache", "_logger"],
    "internal": ["GetClaimsFromToken"]
  },
  "call_graph": {
    "ValidateToken": ["ParseJwt", "_cache.Get", "_logger.Log"],
    "RefreshSession": ["ValidateToken", "ParseJwt", "_db.Update"]
  },
  "summary": "Servicio de autenticación JWT. Valida, renueva y revoca tokens. Usa caché interno para reducir llamadas a base de datos. Punto de complejidad: RefreshSession (CC=14) — lógica de renovación con múltiples casos de expiración."
}
```

## Campos Obligatorios vs Opcionales

| Campo | Nivel | Herramienta mínima |
|-------|-------|--------------------|
| `meta.file` | Obligatorio | — |
| `meta.language` | Obligatorio | extensión del fichero |
| `meta.lines` | Obligatorio | wc -l |
| `structure.classes[].name` | Obligatorio | grep-structural |
| `structure.classes[].line` | Obligatorio | grep-structural |
| `structure.classes[].methods` | Condicional | tree-sitter |
| `structure.functions` | Obligatorio | grep-structural |
| `imports` | Opcional | tree-sitter o grep |
| `complexity.hotspots` | Recomendado | grep count |
| `api_surface` | Opcional | nativa semántica |
| `call_graph` | Opcional | semgrep / nativa |
| `summary` | Obligatorio | generado por Claude |

## Niveles de extracción

### Nivel 1 — Superficial (grep-structural, 0 deps)

Campos disponibles: `meta.*`, `structure.classes[].{name, line}`,
`structure.functions[].{name, line}`, `complexity.total_decision_points`.

Tiempo: < 500ms. Cobertura: ~70%.

### Nivel 2 — Estructural (tree-sitter)

Añade: `structure.classes[].{methods, properties, modifiers}`,
`structure.enums`, `imports`, `complexity.hotspots`.

Tiempo: 1-3s. Cobertura: ~95%.

### Nivel 3 — Semántico (herramienta nativa del lenguaje)

Añade: `api_surface`, `call_graph`, `structure.classes[].base_class`,
tipos completos en métodos y propiedades.

Tiempo: 2-10s. Cobertura: 100% (si herramienta disponible).

## Degradación y valores por defecto

Si un campo no se puede extraer:
- `call_graph`: `{}` (vacío)
- `api_surface.public`: lista de nombres detectados como públicos por nombre (sin `_` prefix)
- `complexity.hotspots`: `[]` si grep falla
- `summary`: `"No se pudo generar resumen automático — revisar manualmente"`

## Ejemplo mínimo (solo grep-structural)

```json
{
  "meta": { "file": "app.py", "language": "python", "lines": 85, "tool": "grep-structural" },
  "structure": {
    "classes": [{ "name": "UserService", "line": 12 }],
    "functions": [{ "name": "get_user", "line": 45 }]
  },
  "imports": {},
  "complexity": { "total_decision_points": 12 },
  "api_surface": {},
  "call_graph": {},
  "summary": "Módulo con 1 clase (UserService) y 1 función libre (get_user). 12 puntos de decisión."
}
```
