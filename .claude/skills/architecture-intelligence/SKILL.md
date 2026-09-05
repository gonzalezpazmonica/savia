---
layer: peripheral
name: architecture-intelligence
description: Usar cuando se diseña o revisa la arquitectura de un proyecto nuevo o existente.
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.category: quality
  savia.maturity: stable
  savia.context_cost: medium
  savia.developer_type: all
  savia.maturity: stable
  savia.priority: medium
  savia.references: "references/patterns-dotnet.md, references/patterns-typescript.md, references/patterns-java.md, references/patterns-python.md, references/patterns-go.md, references/patterns-rust.md, references/patterns-php.md, references/patterns-mobile.md, references/patterns-ruby.md, references/patterns-legacy.md, references/patterns-terraform.md"
  savia.summary: "Detecta patrones de arquitectura en 16 lenguajes. Analiza estructura de carpetas, dependencias y naming. Output: patron detectado + sugerencias de mejora."
  savia.tags: "architecture, patterns, detection, recommendations"
---

# Architecture Intelligence — Skill

> Detección, análisis y recomendación de patrones de arquitectura para los 16 lenguajes soportados.

---

## Algoritmo de Detección

La detección de patrones sigue 4 fases con scoring acumulativo:

### Fase 1: Análisis de Estructura de Carpetas (peso: 40%)

Buscar carpetas que correspondan a patrones conocidos:

| Patrón | Carpetas esperadas |
|--------|-------------------|
| Clean Architecture | `Domain/`, `Application/`, `Infrastructure/`, `Presentation/` |
| Hexagonal | `ports/`, `adapters/`, `domain/` o `core/` |
| DDD | Carpetas por dominio: `orders/`, `users/`, `billing/` |
| CQRS | `commands/`, `queries/`, `handlers/` |
| MVC | `controllers/`, `models/`, `views/` |
| MVVM | `viewmodels/`, `views/`, `models/` |
| Microservices | Múltiples `Dockerfile`, `docker-compose.yml`, API gateway config |

### Fase 2: Análisis de Imports/Dependencias (peso: 30%)

Verificar dirección de dependencias:
- Clean/Hexagonal: Domain NO importa Infrastructure → ✅
- Domain importa Infrastructure → ❌ violación
- Dependencias circulares → ❌ violación
- Buscar: MediatR, Axon, EventStore → CQRS/Event-Driven

### Fase 3: Análisis de Naming Conventions (peso: 20%)

Buscar sufijos/prefijos indicativos:
- `*Controller`, `*Service`, `*Repository` → MVC/Layered
- `*Command`, `*Query`, `*Handler` → CQRS
- `*Aggregate`, `*ValueObject`, `*DomainEvent` → DDD
- `*Port`, `*Adapter` → Hexagonal
- `*ViewModel`, `*Presenter` → MVVM/MVP
- `*UseCase`, `*Interactor` → Clean Architecture

### Fase 4: Análisis de Configuración (peso: 10%)

Buscar ficheros de configuración:
- `docker-compose.yml` con múltiples servicios → Microservices
- DI container config → Clean/Hexagonal
- Event bus config → Event-Driven
- API gateway config → Microservices

### Scoring

Cada patrón recibe score 0-100. Se reporta:
- **Patrón principal**: score más alto
- **Patrones secundarios**: scores >30 que no son el principal
- **Nivel de adherencia**: Alto (>80), Medio (50-80), Bajo (<50)
- **Violaciones**: reglas rotas del patrón detectado

---

## Fitness Functions — Templates

### Regla: No dependencias inversas entre capas

```
RULE: "Domain layer independence"
CHECK: Files in {domain_folder} do NOT import from {infrastructure_folder}
SEVERITY: CRITICAL
```

### Regla: Naming conventions

```
RULE: "Controller naming"
CHECK: Files in {controllers_folder} end with "Controller" suffix
SEVERITY: WARNING
```

### Regla: No dependencias circulares

```
RULE: "No circular dependencies"
CHECK: Module dependency graph has no cycles
SEVERITY: CRITICAL
```

### Regla: Tamaño de módulos

```
RULE: "Module size limit"
CHECK: Each module/package has ≤ {max_files} files
SEVERITY: WARNING
```

---

## Integración con Language Packs

Para cada lenguaje, cargar el reference correspondiente:
- Detectar lenguaje del proyecto (por extensiones, package manager, framework)
- Cargar `references/patterns-{lang}.md` para markers específicos
- Combinar con reglas genéricas de `@docs/rules/domain/architecture-patterns.md`

## Output

Los templates de output están definidos en cada comando (`/arch-detect`, `/arch-suggest`, `/arch-recommend`).
Output se genera en `output/architecture/{proyecto}-{tipo}.md`.
