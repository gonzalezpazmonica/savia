---
name: zeroclaw
description: "Interface with ZeroClaw ESP32 — setup, test, send commands, flash firmware."
argument-hint: "setup | test | ping | led | info | sensors | flash | interactive"
allowed-tools: [Read, Bash, Write]
model_tier: mid
context_cost: low
tier: core
---

# /zeroclaw — ZeroClaw ESP32 Interface

> Regla de seguridad: `@docs/rules/domain/robotics-safety.md`

## Subcomandos

### `/zeroclaw setup`

Primera vez: instala deps, detecta ESP32, flashea MicroPython, despliega firmware.

```bash
bash zeroclaw/setup.sh
```

### `/zeroclaw test`

Self-test: ping, info, LED, sensors, GPIO.

```bash
python3 zeroclaw/host/bridge.py --test
```

### `/zeroclaw interactive`

Modo interactivo: envía comandos al ESP32 desde la consola.

```bash
python3 zeroclaw/host/bridge.py --interactive
```

### `/zeroclaw ping`

Verificar conexión.

```bash
python3 -c "
from zeroclaw.host.bridge import ZeroClawBridge
b = ZeroClawBridge()
b.connect()
print(b.ping())
b.close()
"
```

### `/zeroclaw led [on|off|blink]`

Control del LED integrado.

### `/zeroclaw network`

Configura WiFi: detecta la red del host, pide password, despliega config al ESP32.

```bash
python3 -c "from zeroclaw.host.network_cli import main; main()" setup
```

Subcomandos: `setup` (wizard), `check` (verificar), `scan` (redes disponibles).

### `/zeroclaw flash`

Re-flashear firmware sin borrar MicroPython:

```bash
bash zeroclaw/setup.sh --skip-flash
```

### `/zeroclaw info`

Muestra: versión, CPU, RAM libre, uptime.

## Restricciones

```
SIEMPRE → Verificar conexión (ping) antes de operar
SIEMPRE → Watchdog activo en el ESP32 (10s timeout)
NUNCA → Flashear sin confirmación del humano
NUNCA → Enviar comandos GPIO sin verificar pinout primero
```
