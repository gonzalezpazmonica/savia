---
layer: peripheral
name: robotica-diseno
description: "Diseño profundo de robótica, automatización y hardware/software para el mundo físico. Usar cuando se diseña un robot, una celda de automatización, integración de sensores, servos, PLCs, visión artificial, o cuando se conecta un agente a hardware físico."
metadata:
  savia.maturity: "stable"
  savia.maturity: stable
  savia.context: "standalone"
  savia.context_cost: "medium"
  savia.category: "domain"
  savia.tags: "robotica, automation, hardware, software, sensores, servos, plc, vision, diseño, mundo-fisico, mhs"
  savia.priority: "high"
  savia.loop_level: "L0"
  savia.trigger_keywords: "robótica, robot, automatización, PLC, servos, sensores, visión artificial, hardware, mundo físico, brazo robótico, liquid handler, MHS"
---

# Skill: Robótica y Diseño de Sistemas Físicos

Habilita a Savia para **diseñar, integrar y operar soluciones en el mundo
físico**: robots, celdas de automatización, electrónica de control,
actuación, sensórica, visión artificial y la capa de interfaz agente↔hardware
(estándares tipo MHS). Accionable (construir/operar), no catálogo.

## Authoritative Paths

> **Lee estos paths antes de actuar. NUNCA asumas firmas, NUNCA inventes paths.**

| Para | Lee este path |
|---|---|
| Plan RBT (verticales V1-V6, fases F1-F4, ejes A-H) | `labs/research/savia-domains-robotica-plan-20260828.md` (vault SaviaLabs) |
| Criterio de evaluación/recomendación (9 dimensiones + CRIT-001) | `docs/domains/robotics/ROBOTICS-CRITERIO-20260828.md` |
| Estándar MHS (drivers agente↔hardware, evidencia de campo) | vault SaviaDomains `robotica/RBT/mhs-model-hardware-standard-20260829.md` |
| Índice cúpula RBT (notas + cross-dominio) | vault SaviaDomains `robotica/RBT/INDEX.md` |
| Cúpula automatización industrial (PLC/SCADA) | vault SaviaDomains `robotica/AUT/INDEX.md` |
| Hipótesis Labs (puerta al mundo físico) | vault SaviaLabs `labs/hypotheses/robotica-puerta-al-mundo-fisico.md` |
| Seguridad humana-robot (estándares) | ISO 10218 · ISO/TS 15066 (industria/cobots); fall-safe cuidado de personas |

**Reglas duras**:
- Cúpulas SaviaLabs/SaviaDomains se leen/escriben SOLO por MCP (`savia-vaults_*`),
  nunca por filesystem.
- CRIT-001: jamás enviar datos del mundo físico (vídeo, mapas, telemetría N3+)
  a proveedor cloud; todo el stack corre local.
- Soberanía: el robot es una tool local de Savia; sin telemetría externa no
  consentida.

## Cuándo usar

- Diseñar un robot/brazo/AMR/humanoide o su control (sim2real, RL, VLA).
- Diseñar una celda de automatización o integrar PLC/SCADA/sensores/servos.
- Conectar un agente a hardware físico (drivers, MCP, state dictionary).
- Visión artificial como sensor de control (cámara→CV→decisión).
- Evaluar/recomendar hardware con criterio (9 dimensiones).

## Cuándo NO usar

- Solo documentación de catálogo (sin diseño/operación) → `tech-writer`.
- Arquitectura de software pura sin hardware → `architecture-intelligence`.
- Preguntas puntuales de electrónica sin diseño → responder directamente.

## Decision Checklist

1. ¿Es N1 (conocimiento genérico) o N2-N4b (datos reales de hogar/empresa)? Si
   es N3+/datos del mundo físico → encriptar/local; nunca cloud (CRIT-001).
2. ¿Se necesita diseño o solo recomendación? Si recomendación de compra →
   aplicar ROBOTICS-CRITERIO (9 dimensiones, filtro soberanía).
3. ¿Hay estándar aplicable? Seguridad: ISO 10218/ISO/TS 15066; interfaz
   agente↔hardware: MHS. Si el hardware no es programable, MHS no aplica aún.

### Abort Conditions

- Hardware sin interfaz programable y sin driver disponible → no prometer
  integración vía MHS; reportar como bloqueante.
- Datos N3+ del mundo físico que no pueden quedarse locales → abortar y
  rediseñar (CRIT-001).

## Workflow

```
Requisito físico (tarea, entorno, presupuesto, soberanía)
    ↓
Seleccionar vertical (V1-V6) y fase (F1-F4) del plan RBT
    ↓
Diseñar: actuación (servos/motores) + sensórica + control (PLC/MCU) + SW
    ↓
Definir capa agente↔hardware (MHS: read/write, state dictionary, MCP)
    ↓
Seguridad (ISO, fall-safe, límites por dispositivo)
    ↓
Validar en sim (MuJoCo/ROS2) → deploy → operar local
```

### Detalle de cada paso

1. **Requisito**: tarea concreta, entorno (casa/lab/fábrica/exterior), coste,
   privacidad. Si es hogar/empresa real → aplicar ROBOTICS-CRITERIO primero.
2. **Vertical/fase**: V1 cocina · V2 limpieza · V3 cuidado · V4 huerta · V5
   atención · V6 industrial; F1 sim → F2 plataforma → F3 vertical → F4 Savia.
3. **Diseño físico**: elegir actuadores (Dynamixel/BLDC+FOC/harmonic/belt),
   sensores (encoders/IMU/F-T/RGB-D), controlador (RP2040/ESP32/STM32/Jetson),
   potencia (BMS, DC-DC, presupuesto).
4. **Capa agente↔hardware**: driver MHS con primitivas read/write, tags con
   características no discernibles de código (peso, límites), fichero de
   referencia, state dictionary en shared memory; control por MCP/CLI/code
   files. Ejecutar comando→medir→ajustar en bucle; empaquetar lo aprendido en
   code files deterministas.
5. **Seguridad**: límites de fuerza/velocidad, detección de personas, fall-safe;
   en laboratorio, límites por dispositivo (como MHS).
6. **Validar/operar**: sim2real local (MuJoCo/mjlab + PPO + BAM + ONNX), luego
   física; operación local con supervisión humana (autonomous-safety).

## Outputs esperados

- Diseño/spec ejecutable de la solución (HW+SW+interfaz agente).
- Nota en cúpula RBT/AUT (MCP `vault_write`) con la decisión de diseño.
- Código/skills reutilizables (drivers, recipes de control, skills de manejo).

## Memory hooks

- Decisión de diseño física → `bash scripts/memory-store.sh save --type decision --title "diseno fisico: <tema>" --content "<resumen>" --source skill:robotica-diseno`
- Recall de stack local → `bash scripts/memory-store.sh recall "robotica hardware"`

## Related

- Skill: `savia-vaults` (acceso a cúpulas) · `spec-driven-development` · `tdd-vertical-slices`
- Rule: `docs/rules/domain/autonomous-safety.md` · CRIT-001 (datos N3+ locales)
- Docs: `docs/domains/robotics/ROBOTICS-CRITERIO-20260828.md` · plan RBT
