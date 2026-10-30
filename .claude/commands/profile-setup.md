---
name: profile-setup
description: Onboarding adaptativo — Savia configura lo que necesita cualquier persona, sea cual sea su oficio (SE-484).
tier: core
---

# /profile-setup — Onboarding adaptativo

**Argumentos:** $ARGUMENTS

Protocolo: `docs/rules/domain/profile-onboarding.md`. Catálogo: `docs/onboarding/capabilities.yaml`.
Motor determinista: `scripts/onboarding-plan.py` (el modelo interpreta; el catálogo decide qué se configura).

## 0. Preparación (invisible)

1. Leer `.claude/profiles/savia.md` y adoptar su voz: femenina, directa, sin emojis.
2. Leer `.claude/profiles/active-user.md` para saber si ya hay perfil.
3. **Agente** (`PM_CLIENT_TYPE=agent`, `AGENT_MODE=true` o YAML con `role: "Agent"`): seguir
   `.opencode/commands/references/profile-agent-setup.md` y no hacer este flujo.
4. **Perfil existente**: mismo flujo, con `--profile-dir` del perfil. El plan muestra solo cambios;
   nada se sobrescribe sin confirmar esa clave (paso 4).

## 1. Presentación

```bash
python3 scripts/onboarding-plan.py present --fallback
```

Imprime la frase corta de identidad de la fuente única (`.claude/profiles/savia.md`, marcador
`<!-- identity:short -->`, SE-483) y la pregunta abierta. Se dice tal cual. Si la fuente aún no tiene
el marcador, el motor imprime «Soy Savia.» y avisa por stderr. Nunca escribir otra versión de la identidad aquí.

Respuesta libre: no se ofrece lista de roles. Después, una sola pregunta: cómo quiere que la llame.

## 2. Interpretación

Mapear la respuesta a ids del catálogo usando `serves` y `description` de cada capacidad:

- cada capacidad propuesta lleva su motivo («médica que investiga → research + knowledge + vertical»);
- si el sector no es software, aplicar las 5 fases de `docs/rules/domain/vertical-detection.md`: con score
  ≥ 25 % proponer `vertical` con `hints` (p. ej. `{"which": ["healthcare"]}`); si ninguna llega, no se propone;
- si la respuesta es ambigua («hago de todo»), proponer `[]`: el motor devuelve `needs_clarification`
  y se repregunta con la técnica de la skill `context-interview-conductor`;
- solo ids que existen en el catálogo; el motor rechaza los inventados.

Mostrar la interpretación y dejar quitar o añadir capacidades (AskUserQuestion multiselección).

La interpretación lleva datos personales: no se escribe en disco. Se pasa al motor por stdin
(`--input -`, con heredoc) en cada llamada, con esta forma:
`{"name", "slug", "role_text", "proposed": [{"id", "reason", "hints"}], "answers": {}, "skipped": []}`.
El `slug` cumple `[a-z0-9][a-z0-9-]*`; el motor lo valida antes de nada.

## 3. Preguntas

```bash
python3 scripts/onboarding-plan.py questions --input - --render askuser   # Claude Code
python3 scripts/onboarding-plan.py questions --input - --render text      # sin herramienta de preguntas
```

- **Claude Code**: AskUserQuestion con `header`, `question`, `multiSelect` y las opciones tal cual
  (la recomendada va primero y marcada). Las opciones no destacadas se eligen con «Otro».
- **OpenCode**: su herramienta de preguntas con los mismos datos; si no existe, el texto numerado.
- De una en una. La persona puede saltar cualquiera: anotar `"<capacidad>.<pregunta>"` en `skipped`;
  queda sin configurar y no se insiste. Sin respuesta ni salto, el plan queda en `pending_questions`.
- Lenguaje llano, sin siglas internas. Si la capacidad tiene `sensitivity.why`, decirlo antes de preguntar.

Anotar cada respuesta (id o etiqueta) en `answers.<capacidad>.<pregunta>`.

## 4. Plan y confirmación

```bash
python3 scripts/onboarding-plan.py plan --input - --profile-dir .claude/profiles/users/<slug>
```

Mostrar en texto llano: qué se escribe (`writes`, con `before` en las sobrescrituras), comandos,
skills y packs que se activan, requisitos externos (`requires`), categorías especiales de datos
(`sensitivity`) con su porqué, el estado de la vertical (`vertical.message` si no hay) y los tres
primeros pasos.

- `needs_clarification` → volver al paso 2 con `clarify.question`.
- `invalid_answers` → repreguntar solo esas. `pending_questions` → volver al paso 3 con `pending`.
- Código 2 (input mal formado): corregir el JSON de entrada, no la respuesta de la persona.
- Confirmación con AskUserQuestion: «Aplicar (recomendada)», «Cambiar algo», «Cancelar».
- Cada `overwrite` se confirma aparte; las no confirmadas no se tocan.

## 5. Aplicación

```bash
python3 scripts/onboarding-plan.py apply --input - --profile-dir .claude/profiles/users/<slug> \
  --confirm [--overwrite tone.md:alert_style ...] <<'JSON' ... JSON
```

Sin `--confirm` no escribe nada. Solo escribe dentro de `.claude/profiles/users/<slug>/` y se niega si
git no ignora ese directorio. `diagnostics` dice qué requisito externo falta (p. ej. el PAT) sin
bloquear el resto. Después: actualizar `active-user.md`.

## 6. Primer paso

Proponer los tres `first_steps` del plan, con su comando. Nunca un `/sprint-status` genérico.

```
Perfil listo — {nombre}
Capacidades: {títulos}
Para empezar: 1) /{paso1}  2) /{paso2}  3) /{paso3}
/profile-edit para cambiar · /profile-setup otra vez para revisar
```
