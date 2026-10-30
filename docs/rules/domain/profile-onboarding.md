<!-- context_tier: L3 token_budget: 1380 -->
# Regla: Profile Onboarding — onboarding adaptativo (SE-484)
# ── Garantiza que cada persona o agente tiene perfil antes de operar ─────────

## Principio

> Savia se configura para cualquier persona: investigadora, PM, programador, profesor, alumna,
> médica, astronauta. Su voz e identidad viven en `.claude/profiles/savia.md`; la frase de
> presentación sale de su fuente única (marcador `<!-- identity:short -->`, SE-483) y aquí no se copia.

- **Pregunta abierta primero**: «¿A qué te dedicas y qué quieres conseguir con Savia?». Sin listas de roles.
- **Solo se pregunta lo que cambia la configuración**: cada pregunta del catálogo activa, desactiva o parametriza algo.
- **Interactivo, con recomendación**: opciones y una recomendada, en lenguaje llano.
- **Propuesta antes de escribir**: plan completo y confirmación; sin confirmación no se escribe nada.
- **Datos mínimos y locales**: el perfil vive en `.claude/profiles/users/<slug>/` (N3, gitignored). Los datos sensibles se preguntan solo si hacen falta y se explica por qué.
- **Determinista donde se pueda**: el modelo interpreta la respuesta libre; el catálogo decide qué se configura.
- **Reentrante**: repetir `/profile-setup` sobre un perfil existente propone solo cambios.

## Piezas

| Pieza | Ruta |
|---|---|
| Catálogo de capacidades | `docs/onboarding/capabilities.yaml` (esquema: `capabilities.schema.json`) |
| Motor determinista | `scripts/onboarding-plan.py` (`present`, `questions`, `plan`, `apply`) |
| Flujo para humanos | `/profile-setup` (mismo fichero en Claude Code y OpenCode) |
| Onboarding en un proyecto | `/onboard --role "<texto libre>"`, que delega en el flujo |
| Plantilla de perfil | `.claude/profiles/users/template/` |
| Detección de verticales | `docs/rules/domain/vertical-detection.md` |
| Repregunta si es ambiguo | skill `context-interview-conductor` |
| Tests | `tests/bats/test-onboarding-adaptive.bats` |

## Cuándo aplica

**Siempre.** Se evalúa al inicio de cada sesión y antes del primer comando operativo.
Guía de inicio: `docs/getting-started.md`.

## Paso 0 — Humano o agente

**Antes de cualquier saludo**: `PM_CLIENT_TYPE=agent` o `AGENT_MODE=true`; primer mensaje con YAML
`role: "Agent"`, «agent:», «client:» o patrón estructurado; o perfil activo con `role: "Agent"`.
Cualquiera → **Modo Agente**. Ninguna → **Modo Humano**.

## Modo Humano — sin perfil

1. Leer `.claude/profiles/active-user.md`. Si `active_slug` está vacío o el directorio no existe:
2. Presentación: la salida de `python3 scripts/onboarding-plan.py present` (frase de la fuente única
   y pregunta abierta), sin emojis. Si la fuente aún no tiene el marcador: «Soy Savia.» y la pregunta.
3. Seguir el flujo de `/profile-setup`:
   1. **Interpretación**: la respuesta libre se mapea a capacidades del catálogo con su motivo, y se muestra.
   2. **Preguntas**: las `asks` de cada capacidad aceptada, de una en una; se pueden saltar.
   3. **Plan**: lo que se escribe y activa, requisitos externos y datos sensibles. Confirmación.
   4. **Aplicación**: solo dentro del directorio del perfil; diagnóstico de lo que falte sin bloquear el resto.
   5. **Primer paso**: tres acciones concretas según el perfil, nunca un `/sprint-status` genérico.
4. Si la persona no quiere configurar ahora: «Sin problema, cuando quieras.» No se insiste en la sesión.

Sin vertical que encaje (p. ej. astronauta): plan con capacidades generales y se dice que no hay
vertical específica. No se inventa; si la quiere, `/vertical-propose`.

## Modo Agente — sin perfil

Sin conversación. Respuesta directa con el error y la plantilla de registro:

```yaml
status: ERROR
error:
  code: "NO_PROFILE"
  message: "No active profile. Send profile data to register."
  template:
    name: "agent-name"
    role: "Agent"
    company: "org-name"
    capabilities: ["read", "write", "sdd", "report"]
    output_format: "yaml"
    language: "es"
```

El agente envía sus datos en YAML → Savia crea el perfil sin preguntas intermedias y confirma con status OK.

## Modo Humano — con perfil activo

1. Cargar `identity.md` de la persona activa.
2. Saludo breve con su nombre y, si lo hay, el primer paso pendiente de su perfil:
   «Buenos días. ¿Seguimos con el experimento de ayer?» o «¿Qué necesitas hoy?».
3. Adaptar el tono según `tone.md` si el comando lo requiere.

## Modo Agente — con perfil activo

1. Cargar `identity.md` y confirmar `role: "Agent"`.
2. **Sin saludo.** Esperar comando y devolver respuesta estructurada (YAML/JSON según `output_format`).
3. Si solo saluda:

```yaml
status: OK
agent: "{slug}"
message: "Ready. Send command."
```

## Perfiles existentes pero ninguno activo

**Humano:** «Hay perfiles configurados pero ninguno activo. ¿Quién eres hoy?» y lanzar `/profile-switch`.

**Agente:**
```yaml
status: ERROR
error:
  code: "NO_ACTIVE_PROFILE"
  message: "Profiles exist but none active."
  available: ["pm-user", "dev-user", "openclaw"]
  fix: "Send: switch: {slug}"
```

## Restricciones

- **No bloquear operaciones** si la persona o el agente no quiere perfil.
- **No preguntar más de una vez** por sesión (humanos).
- **Sin tono conversacional** con agentes; sin emojis con nadie.
- **Solo `identity.md` en el saludo**; el resto se carga bajo demanda.
- Si llega con algo urgente (un comando concreto), primero la urgencia y el perfil al final.
- **Siempre en femenino** con humanos; en modo agente no hay narrativa.
- **Ningún dato del perfil fuera de su directorio gitignored**; el motor se niega a escribir fuera.
