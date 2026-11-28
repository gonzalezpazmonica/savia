# SE-537 S0 — Medición de `claude -p` persistente en stream-json (Linux)

- Fecha: 2026-11-28. Máquina: Linux 7.0.0-44, Claude Code 2.1.330. Solo Linux; el Mac queda al final.
- Cierra la pregunta abierta 1 de SE-537 para Linux y da la base de D2. No toca código de producto.
- Coste total de la medición: unos 0,8 USD, casi todo del primer turno con la configuración completa y de las pasadas con Sonnet (ver 7). El resto, con Haiku, costó menos de 0,03 USD.

## 0. Método

Driver en Python (`medir-stream-json-driver.txt`, junto a este fichero; con extensión `.txt` porque no es código de producto y el gate TDD pide un test por cada `.py`). Lanza el proceso una vez, escribe un mensaje JSON por turno en stdin, espera el evento `result` y registra cada línea de stdout con el tiempo desde el envío del turno. Resúmenes: `medir-stream-json-resumen.txt` y `-latencias.txt`.

Proceso medido (flags comprobados con `claude --help`; `--verbose` y `--replay-user-messages` los añade el driver):

```
claude -p --input-format stream-json --output-format stream-json --verbose \
  --include-partial-messages --replay-user-messages \
  --model claude-haiku-5-5 --setting-sources project --strict-mcp-config \
  --disable-slash-commands --permission-mode <manual|acceptEdits|plan>
```

Notas:
- `--output-format stream-json` exige `--verbose` con `-p`.
- Directorio de trabajo: `/tmp/se537m/w_<caso>`, vacío y fuera del repo. Prompts inocuos.
- La configuración «lean» (`--setting-sources project --strict-mcp-config --disable-slash-commands`) evita cargar los hooks, MCP y skills del usuario. La sesión real de Sonora cargará el contexto del workspace de Savia: ver 7.
- `--permission-mode` solo acepta `acceptEdits, auto, bypassPermissions, manual, dontAsk, plan`. No se midió `auto`, `dontAsk` ni `bypassPermissions`.
- `--permission-prompt-tool` no sale en `--help`, pero el flag existe (`stdio`) y `--permission-prompts host|none` sí.

## 1. Varios turnos sobre el mismo proceso: mantiene la sesión

```
python3 -I driver.txt t1.jsonl 90 -- --model haiku --permission-mode plan -- \
  "Recuerda la palabra clave: NARANJA. Responde solo OK." \
  "¿Cuál era la palabra clave? Responde solo la palabra." "Di solo: tres"
```

Salida recortada (`result.result` de cada turno): `OK` → `NARANJA` → `tres`. El `session_id` es el mismo en los tres (`38b96497-…`), el proceso sigue vivo entre turnos y termina con rc 0 al cerrar stdin.

- Cada turno emite otro `system/init` y un `result` propio (`num_turns: 1` por turno). El `init` repetido no indica sesión nueva.
- El proceso acepta mensajes aunque el turno anterior siga sin resolver, pero los encola: con la sesión bloqueada (ver 2), el turno siguiente quedó sin respuesta hasta resolver el primero.
- Con `--model haiku` el `modelUsage` salió como `claude-sonnet-5-5`. Con el id completo `claude-haiku-5-5` sí fue Haiku. Pasar siempre el id completo.

## 2. Herramienta que pide permiso

Prompt: «Usa la herramienta Bash para ejecutar exactamente: `touch b.txt && echo hecho`» (y, en una pasada previa, un `Write` de `a.txt` y `echo hi`). Cada caso con un segundo turno «Di solo: seguimos».

| Caso | Qué llega | ¿Petición de permiso? | ¿Se cuelga? | Efecto |
|---|---|---|---|---|
| `manual`, sin más | `system/permission_denied` (`tool_name`, `tool_use_id`, `message`), luego un `tool_result` con `is_error:true`; `result.permission_denials` lo lista | No: evento informativo | No: el turno acaba en ~4,8 s | Rechazo inmediato; el modelo explica que no pudo |
| `manual` + `--permission-prompts none` | Igual, con `decision_reason_type: asyncAgent` y «no approval surface in this session; permission request denied automatically» | No | No | Rechazo |
| `manual` + `--permission-prompt-tool stdio` | Línea `{"type":"control_request","request":{"subtype":"can_use_tool",…}}` en stdout. Campos de `request`: `tool_name`, `tool_use_id`, `input`, `display_name`, `description`, `blocked_path`, `permission_suggestions`, `subtype` | **Sí**, es la petición real | **Sí, si nadie contesta** (sin respuesta en 40 s; el turno 2 tampoco respondió) | Con `control_response` `behavior:"allow"` + `updatedInput` la herramienta corre (`b.txt` creado, turno en 3,3 s). Con `deny` + `message` llega `tool_result` `is_error:true` con ese mensaje |
| `acceptEdits` | `Write` a `a.txt` y `Bash touch b.txt` (dentro del cwd) corren sin evento | No | No | Se ejecutan |
| `acceptEdits` + `stdio`, `touch` fuera del cwd | `can_use_tool` (con `decision_reason_type`, sin `blocked_path`) | Sí | Solo si no se contesta | Con `deny`, no se ejecuta |
| `plan` (con y sin `stdio`) | Ningún evento de permiso; el modelo se niega a ejecutar y dice que plan mode está activo | No | No | Solo escribe el fichero de plan, que va a **`~/.claude/plans/…md`**, fuera del cwd (efecto lateral; dejé 2 ficheros ahí y no puedo borrarlos con las normas de este trabajo) |

Extractos:

```
# manual, sin tool:
1.733 system permission_denied {"tool_name":"Bash","message":"touch in '/tmp/se537m/w_man_host/b.txt' needs approval. The path is inside the working directories…"}
4.782 result success  denials=[{'tool_name':'Bash', …}]

# manual + stdio, deny:
2.700 can_use_tool Bash input={"command":"touch b.txt && echo hecho",…} keys=[blocked_path, description, display_name, input, permission_suggestions, subtype, tool_name, tool_use_id]
2.723 control_response {"behavior":"deny","message":"denegado por Sonora: aprobar en la terminal"}
```

Observaciones:
- En `manual` sin herramienta de permisos, el modelo **reintentó el mismo `touch`** en el turno siguiente («Di solo: seguimos» → otra llamada a `touch`, otro `permission_denied`). Un rechazo no queda recordado como decisión de sesión.
- `echo hi` corre sin permiso en `manual` (comando de solo lectura). `touch` dentro del cwd pide permiso en `manual` y no en `acceptEdits`.

## 3. Interrumpir un turno sin matar el proceso

Mecanismo: mensaje JSON `{"type":"control_request","request_id":"int1","request":{"subtype":"interrupt"}}` por stdin.

Caso A, generación larga (1 a 400 en palabras), interrupción a los 3,08 s:

```
3.077 interrupt_sent
3.087 control_response {"subtype":"success","request_id":"int1","response":{"still_queued":[]}}
3.093 user  [{"type":"text","text":"[Request interrupted by user]"}]
3.097 result error_during_execution
# turno 2 en el MISMO proceso, mismo session_id:
1.110 result success  "vivo"
```

La confirmación llegó 10 ms después del envío y el siguiente turno funcionó.

Caso B, interrupción con un `can_use_tool` pendiente (nadie contestaba), a los 6,07 s:

```
6.075 control_cancel_request {"request_id":"<id del can_use_tool>"}
6.075 control_response success
6.079 user tool_result "The user doesn't want to proceed with this tool use…"
6.085 result error_during_execution stop_reason=tool_use  denials=[Bash touch c.txt]
# turno 2: "vivo" en 0,70 s
```

La interrupción desbloquea la petición de permiso (emite `control_cancel_request` para ella) y la sesión sigue viva. El `result` de un turno interrumpido es `subtype:"error_during_execution"`, distinto de `success`.

## 4. Tiempos (Haiku, config lean, 3 repeticiones; Sonnet, 1)

Texto parcial = `stream_event` `content_block_delta` de tipo `text_delta`. Tiempos desde el envío del turno.

| Modelo | Turno | 1.er texto parcial | Fin de turno | Deltas | Hueco medio / máximo entre deltas |
|---|---|---|---|---|---|
| Haiku 5.5 | 1 (frío) | 1,36 / 1,53 / 1,44 s | 2,34 / 2,37 / 2,66 s | 37–57 | 0,02 s / 0,06–0,14 s |
| Haiku 5.5 | 2 y 3 | 0,64–0,73 s | 0,90–0,97 s | 7–14 | 0,02–0,03 s / 0,10–0,27 s |
| Sonnet 5.5 | 1 | 2,12 s | 3,44 s | 40 | 0,03 s / 0,23 s |
| Sonnet 5.5 | 2 y 3 | 0,77–0,85 s | 1,33–1,41 s | 13 | 0,03–0,04 s / 0,24–0,46 s |

- Arranque del proceso hasta el primer `system/init`: 0,4–0,8 s en lean. Con la configuración completa, el `init` llegó a los 4,1 s (hooks `SessionStart` unos 2 s).
- Con la configuración completa (Sonnet, 125 k tokens de caché a crear), el primer turno de «Responde solo OK» tardó 7,4 s en terminar y los dos siguientes 1,5 y 1,0 s.
- Los deltas llegan cada ~20–40 ms: basta para trocear en frases con el separador existente sin esperar al final.
- La API cacheó el prompt entre turnos (`cache_read_input_tokens` 28 k–77 k en los turnos 2 y 3).

## 5. Sin red (`bwrap --unshare-net`)

`unshare -rn` falla en esta máquina: `unshare: error de escritura /proc/self/uid_map: Operación no permitida` (`kernel.apparmor_restrict_unprivileged_userns=1`). Se usó `bwrap --unshare-net --dev-bind / /`, que aísla la red igual (queda solo `lo`; `getent hosts api.anthropic.com` no resuelve):

```
timeout 280 bwrap --unshare-net --dev-bind / / python3 -I driver.txt n1.jsonl 120 -- \
  --model claude-haiku-5-5 --setting-sources project --strict-mcp-config \
  --disable-slash-commands --permission-mode manual -- "Di solo: uno" "Di solo: dos"
```

Salida recortada:

```
1.444 system api_retry {"attempt":1,"max_retries":10,"retry_delay_ms":512,"error_status":null,"error":"unknown"}
1.966 attempt 2 (1145 ms)  3.122 attempt 3 (2144)  5.272 attempt 4 (4870)
10.151 attempt 5 (8567)  18.726 attempt 6 (16745)  35.487 attempt 7 (33588)
69.083 attempt 8  102.469 attempt 9   (turno 2 enviado a los 120 s; attempt 10 a +16 s)
…
~175 s después del envío del turno 1:
  result {"subtype":"success","is_error":true,"result":"API Error: Can't reach the API server — check your internet or DNS (EAI_AGAIN)","duration_ms":175535}
```

- **Sin red, el proceso no falla rápido**: reintenta 10 veces con retroceso exponencial (hasta ~34 s de espera) y devuelve el error a los ~176 s. Un turno colgado casi 3 minutos no sirve a la voz.
- Sí hay señal temprana: el primer `system/api_retry` llega a **1,4 s** y trae `attempt`, `max_retries`, `retry_delay_ms` y `error`. Sonora puede mostrar «sin conexión» ahí.
- El `result` final es `subtype:"success"` con `is_error:true` y el texto del error en `result`. No hay `error_status`. Un cliente que solo mire `subtype` lo tomaría por respuesta válida y lo leería en voz alta.
- El mensaje del turno 2 quedó encolado detrás del turno 1, y mi driver atribuyó al turno 2 el `result` del turno 1. La cola de turnos de Sonora no puede asumir un `result` por mensaje cuando hay errores.
- No se midió la **caída de red a mitad de sesión** (red buena y luego cortada). Queda pendiente.

## 6. Conclusiones para D2

1. **El proceso persistente funciona**: mismo `session_id` durante varios turnos, un `result` por turno, arranque de 0,4–0,8 s (lean). El coste de arranque se paga una vez.
2. **Para los permisos hay dos opciones medidas y una trampa.**
   - Con `--permission-prompt-tool stdio` llega una petición `can_use_tool` con la herramienta, su entrada y la ruta bloqueada. Es lo que permite el texto «necesito tu permiso en la terminal».
   - Pero **si Sonora no contesta, la sesión se cuelga sin límite**. Sonora debe responder `deny` al instante con un mensaje fijo y mostrar el texto en pantalla. Nunca `allow` por voz.
   - Sin esa herramienta (o con `--permission-prompts none`) no hay petición: solo `permission_denied` y rechazo inmediato, sin riesgo de colgado. El detalle de la herramienta queda en ese evento y en `result.permission_denials`, y basta para el texto.
3. **Modo recomendado para la voz: `manual`** (con `stdio` y deny automático, o con `--permission-prompts none`). `acceptEdits` ejecuta escrituras y `touch` dentro del cwd sin avisar: demasiado para un canal de voz sin revisión. `plan` no sirve como modo de trabajo y escribe en `~/.claude/plans/`.
4. **Un `deny` no es memoria**: el modelo reintentó la misma orden en el turno siguiente. Cada reintento genera otro `can_use_tool` o `permission_denied`; Sonora debe agrupar por comando y no abrir un aviso visible por cada uno.
5. **`request_cancel_execution` = mensaje `interrupt` por stdin.** Confirma en ~10 ms, deja el proceso y la sesión vivos, y desbloquea un permiso pendiente. Es distinto de `interrupt_speech`, que no toca el proceso. El fin se detecta por `result.subtype == "error_during_execution"`.
6. **Detectar la «sesión sin red» con `system/api_retry`** (1,4 s), no con el `result` (176 s). Al primer `api_retry` con `error:"unknown"` (o tras N intentos): decir la frase fija de D5 y mostrar el estado. Después conviene enviar `interrupt` para soltar el turno en vez de dejar al proceso reintentando con el siguiente turno encolado. Falta medir si un `interrupt` corta los reintentos.
7. **Un `result` con `is_error:true` y `subtype:"success"` no es una respuesta.** El parser debe comprobar `is_error` y no sintetizar voz con el texto de un error de API.
8. **Troceado en frases desde el streaming**: texto parcial a ~0,65–0,85 s en turnos calientes y 1,4–2,1 s en el primero (lean); deltas cada 20–40 ms. La frase 1 puede encolarse antes de `turn-finished` con holgura.
9. Pasar el id completo del modelo (`claude-haiku-5-5`, no `haiku`) si Sonora fija el modelo.

## 7. Límites de esta medición

- **Configuración lean, no la de producción.** La sesión de Sonora arrancará en el workspace de Savia con `CLAUDE.md`, hooks, MCP y skills. Con la configuración completa, el primer turno de «Responde solo OK» (`--permission-mode plan`, cwd `/tmp`, Sonnet) creó 124 938 tokens de caché, costó 0,50 USD y tardó 7,4 s, frente a ~2,3 s lean con Haiku. Eso puede dominar la latencia y el coste reales. Hay que medirlo con el directorio de Savia.
- Muestras pequeñas (3 repeticiones con Haiku, 1 con Sonnet): orden de magnitud, no percentiles.
- Solo texto con herramientas triviales. No se midió un turno con varias herramientas ni con subagentes, que son los que alargan el silencio antes de la primera frase.
- No se midieron `default`, `auto`, `dontAsk` ni `bypassPermissions`.
- Pendiente: `--resume` tras reiniciar el proceso (para recuperar la sesión si muere), consumo de memoria del proceso persistente y turnos de varios minutos.

## 8. Qué queda por medir en el Mac

1. Que `claude --help` del Mac tenga los mismos flags (`--permission-prompt-tool`, `--permission-prompts`, `--include-partial-messages`, `--replay-user-messages`) y la misma versión de Claude Code.
2. La cuenta: en el Mac del trabajo vale solo la cuenta de la organización. Repetir 1–5 con ella; las condiciones de la organización pueden bloquear `-p` o limitar el modelo.
3. Latencia real (primer texto parcial y fin de turno) con el directorio de Savia, con hooks y contexto completos, y con el modelo que decida la persona.
4. `unshare` no existe en macOS: la prueba sin red debe hacerse de otra forma (cortar el wifi o `pfctl`). Medir ahí el tiempo hasta el primer `api_retry` y hasta el error final, y la caída de red a mitad de sesión.
5. Si `manual` + `stdio` se comporta igual (campos de `can_use_tool`; que no se cuelga si Sonora responde en menos de 100 ms).
6. Si en el Mac hay una pasarela de sesión de Space o Soul que sustituya a la CLI (pregunta abierta 2).
7. Si algún sandbox del sistema impide a la app lanzar `claude` como proceso hijo y dónde escribe los planes (`~/.claude/plans/`).

## 9. Reproducir

Los logs en bruto quedaron en `/tmp/se537m/*.jsonl` en la máquina de medición. No se versionan: llevan firmas de `thinking`, `session_id` y rutas locales. Para repetir un caso: `cd` a un directorio vacío fuera del repo y `python3 -I medir-stream-json-driver.txt <log> <timeout_s> [--interrupt-after S] -- <flags> -- <prompt1> [<prompt2>…]`, con `PERM=allow|deny|silent` para decidir cómo contesta el driver a `can_use_tool`.
