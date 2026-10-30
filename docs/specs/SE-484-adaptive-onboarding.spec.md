---
status: APPROVED
priority: P1
developer_type: agent-single
created: 2026-10-30
approved_at: 2026-10-30
author: Savia
phase: D
risk: L2
related_specs: [SE-483, SPEC-110]
origin: decisión de la operadora 2026-10-30 (AskUserQuestion) — «Desarrolla un proceso de onboarding interactivo e inteligente que le ayude a configurar lo que necesite, sea investigador/a, pm, programador, profesor, alumno, médico, científico, astronauta… lo que sea.»
timeline:
  - from: "2026-10-30"
    learned: "2026-10-30"
    value: "APPROVED"
    source: "spec-lifecycle:auto"
---
# SE-484 — Onboarding adaptativo: Savia se configura para cualquier persona

## Problema

El onboarding actual es el de una herramienta de PM:

- `profile-onboarding.md` y `/profile-setup` piden nombre, rol, empresa y proyectos;
- ofrecen roles de PM primero («PM / Scrum Master, Tech Lead…»);
- `/onboard` solo tiene checklist para `--role pm`.

Savia ya tiene piezas para otros perfiles, pero el onboarding no las conecta:

- verticales: educación, finanzas, salud y legal;
- Savia School;
- dominios profesionales;
- Labs, Vaults, Yema y los harnesses.

Alguien que llega como médica, profesor, alumna o astronauta no recibe ninguna configuración útil.

## Principios

1. **Pregunta abierta primero.** «¿A qué te dedicas y qué quieres conseguir con Savia?» La respuesta libre se interpreta; no se elige de una lista cerrada.
2. **Solo se pregunta lo que cambia la configuración.** Cada pregunta existe porque su respuesta activa, desactiva o parametriza algo concreto. Sin preguntas de relleno.
3. **Interactivo, con recomendación.** Toda decisión se presenta con opciones y una recomendada (AskUserQuestion o su equivalente en cada frontend), en lenguaje llano y sin siglas internas.
4. **Propuesta antes de escribir.** Savia muestra el plan de configuración completo y solo escribe tras la confirmación.
5. **Datos mínimos y locales.**
   - El perfil vive donde ya vive (N3: `.claude/profiles/users/<slug>/`, gitignored).
   - Nada personal en el repo público.
   - Los datos sensibles (salud, por ejemplo) se tratan como tales, se preguntan solo si hacen falta y se explica por qué.
6. **Determinista donde se pueda.** El mapeo de perfil a capacidades está en un catálogo versionado, no en la improvisación del modelo. El modelo interpreta la respuesta libre; el catálogo decide qué se configura.
7. **Reentrante.** `/profile-setup` sobre un perfil existente propone solo cambios, y se puede repetir.

## Diseño

### Catálogo de capacidades (`docs/onboarding/capabilities.yaml`)

Por cada capacidad:
- `id` y descripción llana;
- `serves`: perfiles y necesidades a los que sirve, como texto de ayuda para la interpretación;
- `asks`: preguntas que necesita, con opciones y recomendada;
- `configures`: ficheros de perfil y claves que escribe, packs que activa, skills y comandos que recomienda;
- `requires`: requisitos externos, como un PAT o Ollama;
- `sensitivity`: el nivel de los datos que pide.

Capacidades iniciales mínimas:
- orquestación de harnesses y proveedores (Claude, Codex, modelos locales);
- investigación (Savia Labs: prerregistro y experimentos);
- conocimiento (Savia Vaults: cúpulas y confidencialidad);
- desarrollo con SDD (lenguajes del language pack);
- gestión de proyectos (Azure DevOps, Jira o Savia Flow);
- enseñanza y aprendizaje (Savia School);
- verticales (salud, legal, finanzas, educación);
- dominios profesionales;
- accesibilidad (perfil de accesibilidad existente);
- tono (`tone.md`).

### Flujo

1. **Presentación.** Una frase, la de SE-483, y la pregunta abierta.
2. **Interpretación.** Savia mapea la respuesta a capacidades candidatas con su motivo (p. ej. «médica que investiga → investigación + conocimiento con confidencialidad alta + vertical salud») y lo muestra.
3. **Preguntas.** Por cada capacidad aceptada, sus `asks`, de una en una, con opciones y recomendación. La persona puede saltar cualquiera.
4. **Plan.** Lista de lo que se escribirá y activará. Confirmación.
5. **Aplicación.** Se escriben los ficheros del perfil, se activan los packs y se ejecutan las comprobaciones de `requires` (diagnóstico claro si falta algo, sin bloquear el resto).
6. **Primer paso.** Tres acciones concretas para empezar según su perfil, nunca un `/sprint-status` genérico.

### Superficies

- `/profile-setup` implementa el flujo.
- `/onboard --role <x>` deja de tener roles fijos: acepta texto libre y delega en el flujo.
- `profile-onboarding.md` describe el protocolo y apunta al catálogo, sin duplicar la presentación (SE-483).
- En OpenCode, el mismo flujo en el comando equivalente. Las preguntas usan la herramienta de preguntas del frontend o, si no existe, preguntas numeradas en texto.

## Criterios de aceptación

- **AC-1:** el catálogo valida contra un esquema (test). Cada `configures` apunta a ficheros, packs o comandos que existen (test de referencias).
- **AC-2:** con fixtures de respuesta libre (investigadora, PM, programador, profesor, alumna, médica, científico, astronauta, y una ambigua «hago de todo»), el mapeo determinista desde las capacidades que el modelo propone produce un plan coherente. Test con las capacidades propuestas como entrada fija, para no depender del modelo en CI.
- **AC-3:** el perfil «astronauta» u otro sin vertical produce un plan con las capacidades generales y declara que no hay vertical específica. Nada de inventarla.
- **AC-4:** sin confirmación no se escribe ningún fichero (test del paso de aplicación en modo simulado).
- **AC-5:** un perfil existente solo recibe cambios propuestos; nada se sobrescribe sin confirmar.
- **AC-6:** ningún dato del perfil sale del directorio de perfiles gitignored. Test que busca rastros en el árbol versionado tras un onboarding simulado.
- **AC-7:** la presentación no tiene emojis y usa la frase de SE-483.
- **AC-8:** el flujo funciona en Claude Code y en OpenCode (smoke dual).

## Fuera de alcance

- Crear verticales nuevas. El onboarding las recomienda si existen y, si no, propone `/vertical-propose`.
- Onboarding de organizaciones enteras (`/onboard-enterprise` sigue igual).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Flujo | `.claude/commands/profile-setup.md` + AskUserQuestion | comando equivalente en `.opencode/commands/` + herramienta de preguntas o texto numerado |
| Catálogo | `docs/onboarding/capabilities.yaml` | el mismo |

### Verification protocol

- [ ] Smoke dual del flujo en modo simulado
- [ ] Tests del catálogo independientes del frontend

### Portability classification

- [x] **DUAL_BINDING**
