---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-22
author: Savia
phase: D
risk: L2
human_surface: true
related_specs: [SE-465, SE-443, SE-442, SPEC-SE-088-UA-ADOPT, SPEC-193, SE-505]
origin: "Estudio de un proyecto público de tutoría con agentes (DeepTutor, Apache-2.0; sin copiar código ni texto), pedido por la operadora el 2026-11-22. De seis lecciones candidatas, el contraste con main f58dd82ce dejó una sola con hueco real. Informe en Savia Labs."
timeline:
  - from: "2026-11-22"
    learned: "2026-11-22"
    value: "PROPOSED"
    source: "orquestadora; encargo de la operadora en el chat del 2026-11-22"
---
# SE-535 — Puerta de entrada de skills externas

## Problema (verificado en origin/main f58dd82ce, 2026-11-22; lectura estática)

Una skill es texto que un agente obedece. Savia tiene una regla contra el envenenamiento de instrucciones entre agentes y un saneado de escrituras en memoria (SPEC-193), pero la entrada de skills de terceros no pasa por ningún control.

1. **El único instalador real enlaza sin leer.** `scripts/ua-install.sh` clona un repositorio externo con `git clone --depth 1`, sin commit fijado; con `--force` hace `git pull`. Después recorre su carpeta `skills/` y enlaza cada directorio con `ln -sfn` en `~/.agents/skills`. Ningún paso abre un `SKILL.md`. Lo que el repositorio externo publique mañana queda instalado en la siguiente ejecución.
2. **Sus dependencias tampoco están fijadas.** `pnpm install --frozen-lockfile` cae a `pnpm install` si falla; lo mismo con `npm`. SE-465 lo tiene registrado como excepción con la decisión D1 sin tomar (`scripts/pinned-installs-exceptions.txt`, línea 9).
3. **Las órdenes de marketplace no tienen implementación.** `/marketplace-install`, `/marketplace-search` y `/marketplace-publish` son tres ficheros de instrucciones para el modelo. Citan `data/marketplace/registry.json`, que no existe, y ningún script. «Validar checksum (si disponible)» es una frase, no una comprobación.
4. **Una spec aprobada se apoya en ese hueco.** SE-443 S2 prevé invocar la comprobación de malware «desde `/marketplace-install`». Hoy no hay código donde colgarla.
5. **No hay registro de procedencia.** Ningún fichero dice qué skill externa está instalada, de qué commit ni desde cuándo.

**Lo que no se ha observado.** Ningún incidente. En la máquina de referencia la integración externa no está instalada (no existen `~/.opencode/understand-anything` ni `~/.agents/skills`); es una sola muestra y no hay dato de otras instalaciones. Por eso la primera decisión es si este camino se conserva.

## Decisiones previas de la operadora

| # | Decisión | Opciones | Recomendada |
|---|---|---|---|
| D1 | Integración externa Understand-Anything (un script, siete órdenes, una skill) | (a) conservarla detrás de la puerta · (b) retirarla por falta de uso | (b) si nadie la usa; (a) en otro caso |
| D2 | Órdenes `marketplace-*` | (a) retirarlas y reanclar SE-443 S2 en la puerta · (b) implementarlas sobre la puerta | (a) |

**Criterio de no construcción.** Si D1 = (b) y no queda ningún otro camino de entrada de skills externas, S1 y S2 no se construyen: se ejecuta solo S3 y la spec se cierra. Una puerta sin nada que entre por ella es código sin consumidor.

## Qué decide esta spec

Un único guion, `scripts/skill-intake.sh`, con dos subórdenes: `check` (solo lectura) e `install`. Toda vía que traiga una skill de fuera del repositorio lo usa; ninguna copia ni enlaza por su cuenta.

| Regla | Contenido |
|---|---|
| R1 Origen fijado | La fuente se identifica por URL y commit completo (40 hexadecimales). Rama, etiqueta o `HEAD` se rechazan. |
| R2 Copia defensiva | Se copia, no se enlaza. Solo ficheros regulares dentro del directorio de la skill. Se rechaza la skill entera ante un enlace simbólico, una ruta que escape del directorio, más de 200 ficheros, más de 5 MB en total o un binario ejecutable. Se quitan los bits de ejecución. |
| R3 Cabecera reducida | Del frontmatter de `SKILL.md` solo se conservan `name`, `description`, `license`, `compatibility` y `metadata`. Cualquier otra clave se retira, en particular las que amplían alcance (`allowed-tools`, `hooks`, `model`, `always`). Cada clave retirada consta en el recibo. |
| R4 Destino separado | Se instala en la capa de usuario, fuera del repositorio. Nunca en `.claude/skills` ni `.opencode/skills`. Si el nombre coincide con una skill propia de Savia, se rechaza. |
| R5 Recibo | `~/.savia/skill-intake.lock.json`: nombre, URL, commit, hash del árbol copiado, fecha, claves retiradas, veredicto y quién confirmó. Estado privado: no se versiona. |
| R6 Fallo en cerrado | Sin veredicto de un escáner, el estado es `sin verificar` y se exige confirmación expresa de la persona, con la lista de ficheros y de claves retiradas delante. En ejecución no interactiva, sin confirmación registrada, sale con error. Un agente nunca confirma. |
| R7 Actualizar es volver a entrar | Cambiar de commit invalida la confirmación anterior. No hay actualización en segundo plano. |
| R8 Sin red al arrancar | La puerta solo corre por orden explícita (regla 19, arranque seguro). |

No es un registro, ni una tienda, ni un mecanismo de publicación. No evalúa la calidad de una skill.

## Lo que he entendido

### Escenas
1. Ejecutas la instalación de la integración externa. Savia responde: «Origen: el repositorio, commit `3f9a…`. Nueve skills, 41 ficheros. He retirado `allowed-tools` de dos de ellas. No tengo veredicto de seguridad. ¿Las instalo?». Contestas que sí. Savia dice dónde quedaron y dónde está el recibo.
2. Una de las skills trae un enlace simbólico que apunta fuera de su carpeta. Savia no instala esa skill, dice cuál es y por qué, y te pregunta si sigue con las demás.
3. Un mes después el repositorio externo tiene commits nuevos. No cambia nada en tu máquina. Para actualizar repites la instalación con el commit nuevo y vuelves a ver la lista.
4. De noche, un agente autónomo intenta instalar una skill externa. La puerta sale con error y deja la petición para cuando vuelvas.

### Palabras de la persona
> «Ok, crea specs con aquellas aportaciones que nos dan valor y añádelos a roadmap.» — 2026-11-22

### Qué SÍ será
- Una pregunta clara antes de instalar texto ajeno que los agentes van a obedecer.
- Un fichero donde ver qué hay instalado y de dónde vino.

### Qué NO será
- No bloquea las skills propias del repositorio ni las que entran por PR revisada.
- No sustituye a la revisión humana del contenido.

### Confirmación
- fecha: pendiente
- respuesta: pendiente. Las escenas no se han enseñado todavía a la operadora por pregunta interactiva; sin esa respuesta literal la spec no pasa a APPROVED (SE-505).

## Slice S0 — Prototipo navegable
- prototipo: `docs/specs/assets/prototipo-SE-535.md` — transcripción de las cuatro escenas con los textos exactos de Savia sobre una skill de prueba. Se crea al aprobar las escenas.

### Confirmación del prototipo
- fecha: pendiente
- respuesta: pendiente

## Slices

| Slice | Entrega | Entrada | Tier |
|---|---|---|---|
| S0 | Prototipo de las escenas | Escenas confirmadas, D1 y D2 decididas | 1 |
| S1 | `skill-intake.sh check`: R1, R2, R3 en solo lectura; informe de lo que se copiaría y lo que se retiraría | S0 confirmado y D1 = (a) | 2 |
| S2 | `skill-intake.sh install`: R4 a R7 y recibo; `ua-install.sh` deja de enlazar y pasa por la puerta con commit fijado | S1 | 3 |
| S3 | Según D2: retirada de las tres órdenes `marketplace-*` y de sus referencias, y reanclaje de SE-443 S2 en la puerta | D2 decidida | 2 |

S1 y S2 son piezas de autoridad: llevan TDD cruzado (tests de dos proveedores, el código pasa ambos).

## Criterios de aceptación

| AC | Criterio | Slice | autoridad_requerida |
|---|---|---|---|
| AC-1 | **Negativo:** fuente con rama, etiqueta o commit abreviado → rechazo, nada copiado | S1 | real |
| AC-2 | **Negativo:** skill con enlace simbólico, con ruta `../` o con binario ejecutable → esa skill se rechaza entera y el informe dice el motivo | S1 | real |
| AC-3 | Skill con `allowed-tools` y una clave desconocida → la copia no las contiene y el informe las lista | S1 | real |
| AC-4 | **Negativo:** nombre igual al de una skill propia → rechazo | S2 | real |
| AC-5 | **Negativo:** `install` no interactivo sin confirmación registrada → sale con error y el destino queda intacto | S2 | real |
| AC-6 | Instalación confirmada → el recibo contiene commit, hash del árbol y claves retiradas, y el hash coincide con lo copiado | S2 | real |
| AC-7 | **Negativo:** segundo `install` con otro commit → vuelve a pedir confirmación; la anterior no vale | S2 | real |
| AC-8 | `ua-install.sh` no contiene `ln -s` hacia directorios de skills ni clona sin commit fijado; el comprobador de SE-465 no necesita excepción para él | S2 | estatica |
| AC-9 | Tras S3 con D2 = (a): ningún fichero del repositorio referencia `marketplace-install`, salvo historial y specs cerradas; SE-443 cita la puerta | S3 | estatica |
| AC-10 | La puerta no se ejecuta en el arranque: la batería de arranque no la invoca | S2 | estatica |

## Fuera de alcance

- Servidores MCP y conectores (SE-443).
- Fijado de dependencias de `npm` y `pip` (SE-465); esta spec solo retira la excepción de `ua-install.sh` si D1 = (a).
- Escáner de contenido de skills. R6 deja el sitio para un veredicto; no lo implementa.
- Plugins del frontend, que tienen su propio mecanismo de instalación.

## Riesgos

- **Falsa seguridad.** Retirar claves de la cabecera no neutraliza el cuerpo de la skill, que sigue siendo texto que un agente lee. La puerta reduce alcance y deja rastro; no certifica. El recibo lo dice con el estado `sin verificar`.
- **Fricción.** Una pregunta por instalación. Es una acción rara y deliberada; no hay ventana de observación porque no hay volumen que medir.
- **Construir sin consumidor.** Mitigado por el criterio de no construcción y por el orden: D1 antes de S1.

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Puerta | `scripts/skill-intake.sh` (común) | El mismo guion |
| Destino de instalación | Capa de usuario fuera del repositorio | La misma ruta |
| Recibo | `~/.savia/skill-intake.lock.json` | El mismo fichero |

### Verification protocol

- [ ] Los tests de S1 y S2 pasan invocando el guion desde ambos frontends
- [ ] No se registra ningún hook nuevo
- [ ] Una skill instalada por la puerta se descubre igual en los dos frontends

### Portability classification

- [x] **PURE_BASH**: un guion común; ningún binding específico de frontend.

## Aprobación

Pendiente. PROPOSED hasta que la operadora decida D1 y D2 y confirme las escenas por pregunta interactiva.
