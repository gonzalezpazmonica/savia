---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-10-23
author: Savia
phase: D
risk: L2
related_specs: [SE-442, SE-454]
origin: triaje de code scanning (PR #1363), alerta #25 py/bind-socket-all-network-interfaces
timeline:
  - from: "2026-10-23"
    learned: "2026-10-23"
    value: "PROPOSED"
    source: "spec-lifecycle:auto"
---
# SE-464 — ZeroClaw: el servidor WiFi del ESP32 acepta órdenes de cualquier equipo de la LAN

## Problema

CodeQL marca `zeroclaw/firmware/lib/wifi_server.py:27` (`bind(('0.0.0.0', 80))`, alerta #25). El bind
no es la causa: el ESP32 tiene una sola interfaz STA y no hay otra dirección a la que atarse. Lo
explotable es lo que hay detrás del socket. Medido sobre `main` (d941dc3a6):

- `MiniHTTPServer` arranca siempre que la WiFi esté conectada (`zeroclaw/firmware/main.py:39-41`), en
  el puerto 80, sin autenticación de ningún tipo.
- `POST /cmd` pasa el cuerpo tal cual a `CommandHandler.process()` (`zeroclaw/firmware/lib/commands.py`).
  Eso incluye `gpio <pin> high|low`, que hace `machine.Pin(pin_num)` sobre **cualquier pin** sin lista
  permitida y lo pone en salida. Un pin conectado a hardware externo o a la flash puede dejar el
  dispositivo o lo que tenga enchufado en mal estado. También `led`, `lcd <texto>` y `ask`.
- Cada respuesta lleva `Access-Control-Allow-Origin: *`. Un `fetch` con `Content-Type: text/plain` es
  una petición simple sin preflight: cualquier web abierta en un navegador de la misma WiFi puede
  mandar órdenes al ESP32 y leer la respuesta. No hace falta estar en la LAN; basta con que la víctima
  visite la página.
- El 500 devuelve `str(e)` al cliente.
- **Nadie en el repo usa esta interfaz.** El host habla con el ESP32 por serie; no hay cliente de
  `/cmd` en `zeroclaw/host/` ni en `scripts/`. `zeroclaw/host/connectivity_test.py` solo hace `GET
  /ping`, y al puerto 8765, no al 80. Los tests (`zeroclaw/tests/test_network.py`) comprueban que el
  fichero existe y su tamaño, no su comportamiento.

## Valor y evidencia

Superficie de control físico abierta a la LAN y, por CORS, a cualquier web. El arreglo es pequeño
porque no hay consumidores que romper. La alerta de CodeQL no desaparece con un token (el bind sigue
siendo `0.0.0.0`); se cierra con un descarte razonado que cite esta spec una vez implementada.

## Alcance

| Slice | Entrega |
|---|---|
| S1 | Servidor HTTP **apagado por defecto**: `main.py` solo lo arranca si `zeroclaw/firmware/config.json` (el mismo fichero que ya lee `boot.py` para `wifi_ssid`) trae `"http_enabled": true` y un `"http_token"` de al menos 32 caracteres. Sin token configurado no arranca y lo dice por serie. |
| S2 | Autenticación: `/cmd` y `/status` exigen `Authorization: Bearer <token>` con comparación en tiempo constante (bucle XOR propio; MicroPython no trae `hmac.compare_digest`). `/ping` queda abierto pero sin IP. Sin cabecera o con token erróneo: `401` sin cuerpo útil. |
| S3 | Sin `Access-Control-Allow-Origin: *`: no se emite cabecera CORS. Un navegador no puede leer la respuesta y la cabecera `Authorization` fuerza preflight, que el servidor no contesta. El 500 responde `{"error":"internal"}`. |
| S4 | `gpio` con lista permitida de pines (constante en `commands.py`, por defecto vacía para la vía HTTP); la vía serie conserva el comportamiento actual. |
| S5 | Tests en CPython sin hardware: `_handle()` y `poll()` con socket falso y `network`/`machine` sustituidos por módulos stub en `sys.modules`. |

## Fuera de alcance

- TLS en el ESP32 (coste de RAM y certificados). El token viaja en claro por la WiFi; se documenta.
- Cambiar el bind: con una interfaz no aporta nada.
- Cliente HTTP en el host: no existe y no se crea aquí.
- Descartar la alerta #25: lo decide la operadora tras el merge.

## Criterios de aceptación

| AC | Verificación |
|---|---|
| AC1 | `python3 -m pytest zeroclaw/tests/test_wifi_server_auth.py` pasa. |
| AC2 | Caso negativo: `POST /cmd` con cuerpo `gpio 4 high` y sin `Authorization` devuelve 401 y el handler stub registra **cero** llamadas. Contra `main` este test falla (hoy responde 200 y llama al handler). |
| AC3 | Token erróneo de la misma longitud y token correcto con un carácter cambiado: 401 en ambos. Token correcto: 200 y una llamada al handler. |
| AC4 | Ninguna respuesta contiene `Access-Control-Allow-Origin` (test sobre los bytes enviados al socket falso). |
| AC5 | `main.py` con config sin `http_token` o con token de menos de 32 caracteres no instancia `MiniHTTPServer` (test con `main` importado contra stubs, o refactor mínimo a una función `should_start_http(cfg)` testeada). |
| AC6 | `gpio` por la vía HTTP con un pin fuera de la lista permitida devuelve error y no llama a `machine.Pin`. |
| AC7 | Prueba en hardware anotada en la PR por la operadora: con token, `curl -H "Authorization: Bearer …" -d 'led on' http://<ip>/cmd` enciende el LED; sin token, 401. Si no hay hardware a mano, la PR lo dice y el AC queda pendiente. |
| AC8 | `wifi_server.py` sigue ≤ 150 líneas (`test_network.py`). |

## Riesgos

- Romper un uso manual no documentado por HTTP. Mitigación: queda opt-in y documentado en
  `zeroclaw/ROADMAP.md` y en el `config.json` de ejemplo (claves vacías).
- `config.json` está versionado (hoy con `wifi_ssid` vacío). El token real nunca se commitea: el
  fichero versionado lleva `"http_token": ""` y el valor se escribe solo en la copia que se sube al
  dispositivo.
- Los stubs de MicroPython pueden ocultar diferencias reales (`socket` de MicroPython). AC7 lo cubre.
- Token en claro en la WiFi: un atacante que escuche la red lo obtiene. Se declara; el modelo de
  amenaza que cierra esta spec es «cualquier equipo o web de la LAN», no «un atacante con captura de
  tráfico».

## Esfuerzo

S1-S3 S, S4 S, S5 S. Total S.

## Decisiones pendientes de la operadora

- **D1**: apagar el servidor HTTP por defecto (propuesta: sí; nadie lo usa).
- **D2**: lista inicial de pines permitidos por HTTP (propuesta: vacía, ampliar cuando haya un uso).

## Referencias cruzadas

PR #1363 (triaje), SE-454 (invariantes negativos: el AC2 sigue ese patrón), SE-442 (CodeQL).

## OpenCode Implementation Plan

### Bindings touched

| Componente | Claude Code | OpenCode v1.14 |
|---|---|---|
| Firmware MicroPython (`zeroclaw/firmware/`) | no depende del frontend | no depende del frontend |
| Tests pytest (`zeroclaw/tests/`) | independientes del frontend | los mismos |

### Verification protocol

- [ ] Los tests corren con `python3 -m pytest` sin frontend ni hardware.
- [ ] Sin hooks, comandos ni agentes nuevos.

### Portability classification

- [x] **PURE_BASH**: firmware y tests sin binding de frontend.
