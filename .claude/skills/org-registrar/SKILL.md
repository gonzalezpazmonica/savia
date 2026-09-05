---
name: org-registrar
description: "Gestiona el grafo de entidades organizacionales (Company as Code, SE-365): valida entidades, indexa el grafo, consulta dependencias y prepara propuestas de escritura mediada. Usar cuando se consultan roles/unidades/personas/políticas/proyectos/recursos, o se propone una entidad nueva."
metadata:
  savia.category: governance
  savia.maturity: stable
  savia.context: fork
  savia.context_cost: low
  savia.maturity: stable
  savia.priority: high
  savia.summary: "Company as Code (SE-365): valida/consulta el grafo organizacional (company/projects/resources) con vocabulario de relaciones controlado y escritura mediada por humano."
layer: peripheral
---

# org-registrar — Grafo organizacional (SE-365)

> Company as Code: entidades organizacionales como código versionable, consultable
> y gobernado por CRITERIO.md. CRIT-001: todo local.

## Cuándo usar

- Consultar "¿qué proyectos usan este recurso?" / "¿qué políticas aplican a esta unidad?"
- Validar una entidad o relación nueva contra el esquema y CRITERIO.md
- Proponer una entidad nueva (escritura mediada: prepara el diff, no lo aplica)

## Comandos

```bash
# validar una entidad
bash scripts/org-registrar.sh validate --file company/policies/policy-x.md

# indexar el grafo de un directorio
bash scripts/org-registrar.sh index --dir company --json

# consultar dependencias de un recurso
bash scripts/org-registrar.sh query --graph graph.json --what uses_resource --id resource-x

# preparar propuesta (no aplica — requiere confirmación humana)
bash scripts/org-registrar.sh propose --file entity.md --out proposals/
```

## Estructura del grafo

```
org/company/roles|units|people|policies/<slug>.md
org/projects/<slug>.md
org/resources/infra|tools|knowledge/<slug>.md
```

> Árbol dedicado bajo `org/`, separado de `projects/` de pm-workspace (protegido por
> `protect-project-privacy`).

## Reglas de gobernanza

1. **Lectura libre** para agentes; **escritura mediada** por humano (se delega la
   ejecución, nunca el criterio).
2. **Vocabulario de relaciones cerrado** (sección 6 del spec SE-365): relación no
   listada → rechazo.
3. **Políticas solo `origin: owner`** (`source: human`); agentes pueden proponer
   (marcan `proposed`).
4. **Recursos**: `sensitivity` nunca `secret` — credenciales nunca viven en el vault.
5. **CRITERIO.md valida, no almacena** — las entidades viven en su propio árbol.
6. Cada escritura emite receipt en el audit ledger (SE-355) con `enforced`.

## Referencias

- Spec: `docs/specs/SE-365-company-as-code.spec.md`
- Dependencias: SE-352 (origin), SE-355 (audit), SE-363 (records), SE-362 (risk)
