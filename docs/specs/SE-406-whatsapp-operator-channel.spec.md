---
status: DEFERRED
deferred_by: "gonzalezpazmonica 2026-10-13, aparcada: los avisos van por la app móvil de Savia Space"
priority: P1
developer_type: agent-team
created: 2026-09-27
phase: B
risk: L4
related_specs: [SE-343, SE-332, SE-349, SE-362, SE-392, SE-401, SPEC-186, SE-304]
origin: "Operadora 2026-09-27: 'convierte a Savia en un harness de IA autónomo que se comunique de forma activa conmigo vía WhatsApp. Analiza, diseña, genera spec y haz una propuesta para revisar.'"
timeline:
  - from: "2026-10-13"
    learned: "2026-10-13"
    value: "DEFERRED"
    source: "spec-lifecycle:manual"
---

# SE-406 — Savia Relay: canal activo con la operadora por WhatsApp

> Estado DEFERRED (aparcada). Los avisos urgentes y el Relay de Soul van por la app móvil de Savia
> Space (SE-430, SE-431 D3). Hoy la app consulta cada 15 minutos o más; se revisa cuando se decida
> el push propio de SE-430 (D3), o si la app no basta para lo urgente. Nada de este spec se
> implementa mientras siga aparcada.
> Las decisiones abiertas están en §10.

## 1. Objetivo

Que Savia trabaje de forma autónoma y **se comunique activamente** con la
operadora por WhatsApp:

- avisa cuando pasa algo que importa (CI rota, PR listo, run bloqueado, handback);
- **pregunta** cuando necesita una decisión, con opciones y recomendación, y
  continúa con la respuesta;
- **recibe órdenes** desde el móvil (estado, pausar, lanzar un sprint nocturno,
  conceder un grant) y las ejecuta dentro de las reglas de autonomous-safety;
- informa del resultado con evidencia (URL del PR, estado de CI).

El objetivo no es un chat libre con un LLM por WhatsApp. Es un **canal operativo
estructurado** entre la operadora y el harness. La distinción es técnica (§5) y
normativa (§3.2).

## 2. Estado actual (análisis)

| Pieza | Qué hay | Hueco |
|---|---|---|
| `docs/rules/domain/messaging-whatsapp.md` | Configuración para `lharries/whatsapp-mcp` (whatsmeow, cliente no oficial, cuenta personal por QR) | Documenta un camino no oficial sobre la cuenta personal; sin implementación activa en scripts |
| `scripts/notify.sh --channel whatsapp` | Acepta el nombre de canal | No envía nada por WhatsApp |
| `/notify-whatsapp`, `/whatsapp-search` | Comandos que dependen del MCP | Requieren sesión humana; no hay emisor de eventos |
| `voice-inbox` | Transcripción local (Faster-Whisper) → intención | No conectado a un canal de entrada |
| `savia-runs.sh` (SE-349) | Estados de runs: `waiting_input`, `blocked`, CI, PR | Nadie avisa a la operadora de las transiciones |
| `handback-resolve.sh` (SE-332) | La cadena de escalado termina en "manual" | "Manual" hoy significa "que la operadora mire la terminal" |
| `operator-grant.sh` (SE-343) | Ledger local de grants con TTL | Solo se concede desde una sesión |
| `savia-automations.sh` (SE-304) | Tareas programadas | Sin canal de salida activo |

Conclusión: las piezas de autonomía (runs, handback, grants, automatizaciones)
existen; falta el **canal bidireccional** y el **supervisor** que convierte
mensajes en trabajo gobernado.

## 3. Opciones de transporte

### 3.1 Comparativa

| | A. WhatsApp Cloud API (Meta, oficial) | B. whatsmeow en número dedicado (no oficial) | C. Telegram Bot API (alternativa) |
|---|---|---|---|
| Cumple términos del servicio | Sí, si el bot es estructurado (§3.2) | No: cliente no autorizado | Sí: bots permitidos explícitamente |
| Riesgo de bloqueo | Bajo | Alto; limitado al número dedicado | Muy bajo |
| Entrada de mensajes | Webhook HTTPS público (túnel saliente, §6.4) | Conexión saliente local, sin endpoint público | Long polling saliente, sin endpoint |
| Coste | Por mensaje entregado; desde 2026-10-01 también las respuestas en ventana de 24 h | Número/SIM | Gratis |
| Mensajes proactivos | Solo plantillas aprobadas fuera de la ventana de 24 h | Libres | Libres |
| Botones / listas | Sí (3 botones, listas de 10) | Limitado | Sí (teclados inline) |
| Datos pasan por | Meta | Meta (E2E) | Telegram (sin E2E en bots) |
| Estabilidad | Alta, versionada | Rompe con cambios de protocolo | Alta |

### 3.2 Política de Meta sobre chatbots de IA

Desde 2026-01-15 la WhatsApp Business Platform prohíbe los **chatbots de IA de
propósito general** (conversación abierta sobre cualquier tema). Permite bots
estructurados de notificaciones, soporte y procesos concretos. Savia Relay
cumple solo si se mantiene como canal operativo de un proceso concreto
(operación del workspace), con gramática cerrada y botones (§5). Un modo "habla
con Savia de lo que quieras" lo convertiría en propósito general. Este punto se
verifica en F0 contra los términos vigentes antes de dar de alta nada.

### 3.3 Recomendación

**A (Cloud API oficial) con un número dedicado a Savia**, detrás de un adaptador
de transporte para poder cambiar a C sin tocar el resto. B se descarta para uso
continuo: un harness autónomo no puede depender de un cliente que viola los
términos y puede perder el número en cualquier momento; y usarlo sobre la cuenta
personal pondría en riesgo la cuenta de la operadora.

Si el coste por mensaje o la verificación de Meta Business resultan un bloqueo
en F0, la alternativa técnicamente más limpia es C (Telegram): mismo diseño,
otro adaptador.

## 4. Arquitectura

```text
            ┌───────────────────────────── WhatsApp (Meta) ─────────────────────────────┐
            │                                                                            │
   webhook (HTTPS, firma HMAC)                                              Graph API (send)
            │                                                                            ▲
            ▼                                                                            │
   ┌──────────────────┐   inbox.jsonl   ┌──────────────────┐   outbox.jsonl   ┌──────────────────┐
   │  relay-receiver  │ ──────────────▶ │   relay-router   │ ───────────────▶ │   relay-sender   │
   │ verifica firma,  │                 │ gramática cerrada│                  │ Shield saliente, │
   │ allowlist, dedup │                 │ decisiones, voz  │                  │ rate limit, horas│
   └──────────────────┘                 └────────┬─────────┘                  └──────────────────┘
                                                 │ intents aprobados                  ▲
                                                 ▼                                    │ eventos
                                        ┌──────────────────┐                ┌──────────────────┐
                                        │  savia-autopilot │ ─────────────▶ │  emisores        │
                                        │ runs gobernados  │  savia-runs,   │ savia-runs,      │
                                        │ (claude -p /     │  handback,     │ handback, CI,    │
                                        │  opencode run)   │  operator-grant│ pr-plan, briefs  │
                                        └──────────────────┘                └──────────────────┘
```

Todo corre en local. Estado en `~/.savia/relay/` (fuera del repo, CRIT-001).

### 4.1 Componentes

1. **relay-receiver** (`scripts/relay/receiver.py`, stdlib, `127.0.0.1:8455`):
   verifica `X-Hub-Signature-256` con el app secret, acepta solo el `wa_id` de la
   operadora, descarta duplicados por `message.id`, persiste en `inbox.jsonl`,
   responde 200 en < 1 s. No interpreta nada.
2. **relay-router** (`scripts/relay/router.py`): lee el inbox, clasifica cada
   mensaje en respuesta a decisión, comando cerrado, nota de voz o texto libre
   (§5), y produce acciones o respuestas.
3. **relay-sender** (`scripts/relay/sender.py`): envía desde `outbox.jsonl`;
   aplica Savia Shield saliente (§6.3), horas de silencio, límite por hora y
   reintentos con backoff.
4. **Emisores de eventos** (`scripts/savia-relay.sh emit <tipo> ...`): llamados
   desde `savia-runs.sh` (transiciones), `handback-resolve.sh` (fin de cadena),
   `pr-plan.sh` (PR creado/fallo), un vigilante de CI (`gh`), y
   `savia-automations.sh` (brief matutino).
5. **savia-autopilot** (`scripts/relay/autopilot.sh`): supervisor que ejecuta
   intents aprobados como runs gobernados por el runtime dual (SE-392):
   rama `agent/*`, PR Draft, time-box, doble opt-in resuelto por grant (SPEC-186),
   registro en `savia-runs.sh`. Informa del resultado por el relay.
6. **Adaptador de transporte** (`scripts/relay/transport_whatsapp.py`,
   `transport_telegram.py`): única pieza que conoce el proveedor.

## 5. Protocolo de interacción

### 5.1 Mensajes salientes

| Tipo | Ejemplo | Formato |
|---|---|---|
| Aviso | "CI roto en #1165: Standards Compliance, 7 reglas > 150 líneas." | texto + enlace |
| Decisión | "SE-404 cambia G13. ¿Merge?" | pregunta + hasta 3 botones, recomendada primero |
| Brief | resumen 09:00 antes de la daily | plantilla aprobada (fuera de ventana) |
| Resultado | "PR #1170 creado, 22/22 gates, CI verde." | texto + enlace |

Cada pregunta lleva un `decision_id` y un nonce. La respuesta solo vale para esa
decisión, una vez, antes de su caducidad (defecto 12 h).

### 5.2 Mensajes entrantes

1. **Respuesta a decisión** (botón o número): se liga a `decision_id`; el run en
   `waiting_input` continúa con esa respuesta.
2. **Comando cerrado** (lista exhaustiva, sin LLM):
   `estado`, `runs`, `prs`, `ci`, `pausa`, `reanuda`, `para todo`,
   `grant <scope> <horas>`, `merge #N`, `sprint <descripción>`, `investiga <tema>`,
   `silencio <horas>`, `ayuda`.
3. **Nota de voz**: se descarga, se transcribe en local (voice-inbox,
   Faster-Whisper) y el texto sigue el camino 2 o 4.
4. **Texto libre**: nunca se ejecuta. El router puede usar un modelo **solo** para
   proponer el comando cerrado más probable ("¿Querías decir `sprint revisar
   CI`? [Sí] [No]"). Sin confirmación, queda como nota en la cola de la próxima sesión.

El texto recibido es siempre **dato**, nunca instrucción para un agente con
herramientas. Un reenvío malicioso no puede convertirse en acción sin pasar por
la gramática cerrada y la confirmación.

### 5.3 Acciones con autoridad

| Acción | Requisito |
|---|---|
| `pausa`, `para todo` | inmediato; `para todo` revoca grants de autonomía y detiene runs (kill switch) |
| `sprint`, `investiga` | grant de autonomía vigente o confirmación en el momento |
| `grant <scope>` | confirmación de dos pasos con código de 6 dígitos que el relay envía |
| `merge #N` | solo PR tier 1/2 (SE-362), CI verde, grant `merge` ligado al número **y al SHA de cabeza**; dos pasos |
| merge tier 3/4 | **no** desde el móvil: requiere revisión explícita del PR concreto (§10, D5) |

Cada acción queda en `output/agent-runs/relay-audit.log` y, si concede autoridad,
en el ledger de `operator-grant.sh`.

## 6. Seguridad

### 6.1 Modelo de amenazas

| Amenaza | Mitigación |
|---|---|
| Webhook falsificado | Firma HMAC obligatoria; sin firma válida, 403 y registro |
| Mensaje de otro número | Allowlist de un único `wa_id`; el resto se ignora sin responder |
| Móvil robado o desbloqueado | Acciones con autoridad en dos pasos; `para todo` siempre disponible; TTL corto de grants; tier 3/4 fuera del canal |
| Prompt injection por texto reenviado | Texto = dato; gramática cerrada; el LLM solo sugiere comandos y se confirma |
| Replay | Dedupe por `message.id`; nonce de decisión de un solo uso con caducidad |
| Fuga de datos de cliente a Meta | Shield saliente (§6.3) |
| Coste o spam | Límite de mensajes por hora y por día; horas de silencio |
| Credenciales | Token de acceso y app secret en `~/.savia/relay/credentials` (600) o gestor de secretos; nunca en el repo ni en mensajes |

### 6.2 Autoridad (SE-401)

Un mensaje es un **Intent**. La **Authority** sale del ledger de grants, no del
mensaje. La **Execution** la hace el autopilot bajo autonomous-safety. La
**Verification** y la **Evidence** vuelven por el canal (URL del PR, estado de
CI). El canal nunca amplía lo que autonomous-safety permite.

### 6.3 Soberanía de datos

Todo texto saliente pasa por Savia Shield (capas 1-3). Contenido de nivel N4/N4b
no sale nunca: se sustituye por "Evento en proyecto privado; detalle en la
terminal". Las notas de voz se transcriben en local.

### 6.4 Exposición del webhook

El receiver escucha solo en `127.0.0.1`. La entrada pública la da un túnel
saliente (Cloudflare Tunnel u otro, §10 D3) limitado a la ruta del webhook. Sin
túnel activo, el canal degrada a solo salida.

## 7. Fases

| Fase | Entrega | Riesgo | Gate de salida |
|---|---|---|---|
| F0 | Decisiones §10, alta en Meta, número, verificación de política, coste real medido | 0 (sin código) | Operadora aprueba F1 |
| F1 | Solo salida: avisos de eventos + brief matutino; `emit` desde runs, handback, CI, pr-plan | Bajo | 1 semana sin fugas en Shield ni spam |
| F2 | Decisiones con botones; runs en `waiting_input` continúan con la respuesta | Medio | 10 decisiones reales resueltas sin error de ligado |
| F3 | Comandos cerrados + kill switch | Medio | `para todo` verificado en caos |
| F4 | Grants y merge tier 1/2 desde el móvil, dos pasos | Alto | Revisión explícita de la operadora |
| F5 | Autopilot: intents aprobados lanzan runs gobernados | Alto | 5 runs completos con evidencia |
| F6 | Notas de voz entrantes | Medio | Precisión de transcripción aceptada |

Cada fase es un PR Draft independiente y revisable.

## 8. Criterios de aceptación (v1 = F1-F3)

- AC1: El receiver rechaza (403) toda petición sin firma válida y registra el intento.
- AC2: Un mensaje de un `wa_id` fuera de la allowlist no produce respuesta ni acción.
- AC3: El mismo `message.id` recibido dos veces produce una sola entrada en el inbox.
- AC4: Un texto saliente con un dato N4 detectado por Shield no se envía; se sustituye por el aviso genérico.
- AC5: Una respuesta a una decisión caducada o ya usada se rechaza con explicación.
- AC6: Un texto libre nunca ejecuta una acción sin confirmación explícita de un comando cerrado.
- AC7: `para todo` revoca los grants de autonomía y deja todos los runs activos en `blocked` en < 10 s.
- AC8: Transición de run a `waiting_input` o `ci_failed` → aviso en < 60 s.
- AC9: Horas de silencio y límite horario respetados (tests con reloj simulado).
- AC10: El transporte es sustituible: la suite de tests corre contra un transporte falso sin red.
- AC11: Tests BATS/pytest sin red real (servidor Meta simulado); auditor ≥ 80.

## 9. Fuera de alcance

- Chat abierto con un LLM por WhatsApp (propósito general, §3.2).
- Mensajes a terceros o grupos: el canal es 1:1 con la operadora.
- Aprobar desde el móvil merges tier 3/4 o cambios en gates.

## 10. Decisiones para la operadora

| # | Decisión | Recomendación |
|---|---|---|
| D1 | Transporte | A: Cloud API oficial; C (Telegram) si F0 revela bloqueo |
| D2 | Número | Número dedicado para Savia, no tu cuenta personal |
| D3 | Túnel del webhook | Cloudflare Tunnel limitado a la ruta del webhook |
| D4 | Qué avisa | CI roto, PR listo, `waiting_input`, handback, brief 09:00; el resto en el brief |
| D5 | Merge desde el móvil | Solo tier 1/2 con CI verde; tier 3/4 exige revisión del PR en escritorio |
| D6 | Horas de silencio | 22:00-08:00 salvo `para todo` y alertas críticas |
| D7 | Presupuesto | Límite diario de mensajes y de tokens del autopilot, fijado en F0 tras medir |
| D9 | Emparejamiento del canal | Emparejamiento por DM con código de un solo uso (patrón verificado en hermes-agent, 2026-09-29) antes de aceptar órdenes |
| D8 | Posición en ADR-002 | Fase B (depende de la autoridad de SE-401); F1 puede entrar antes por bajo riesgo |

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Relay (receiver, router, sender) | procesos Python locales | idéntico |
| Autopilot | `claude -p` vía runtime dual (SE-392) | `opencode run` vía runtime dual |
| Emisores | llamadas bash en scripts existentes | idéntico |

### Verification protocol

- [ ] El autopilot lanza el mismo intent con ambos frontends (test con CLI simulado)
- [ ] El relay no depende de ningún frontend
- [ ] Sin hooks nuevos de frontend en v1

### Portability classification

- [x] **DUAL_BINDING**: el relay es independiente del frontend; el autopilot usa el runtime dual SE-392 desde F5.
