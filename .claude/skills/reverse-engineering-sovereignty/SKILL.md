---
layer: peripheral
name: reverse-engineering-sovereignty
description: Usar cuando se necesita comprobar qué hace un software opaco del que se depende, o poder salir de él, mediante ingeniería inversa autorizada con REA externo.
metadata:
  savia.category: governance
  savia.maturity: beta
  savia.context_cost: medium
  savia.dependencies: ""
  savia.priority: medium
  savia.summary: "Ingeniería inversa para la soberanía tecnológica: comprobar lo que hace el software opaco y poder salir de él. Puerta de autorización A-D, líneas rojas e informe por clases de evidencia."
  savia.tags: "sovereignty, reverse-engineering, rea, exit-plan, evidence"
---

# Skill: Reverse Engineering Sovereignty

> SE-455. Complementa `sovereignty-auditor` (dimensión opcional «software opaco») y `/legacy-assess` (sin fuentes).
> Marco ético: `docs/rules/domain/savia-ethical-principles.md`. Propósito: **comprobar y poder salir**. Nunca atacar.

## Para qué sirve

Tres preguntas que solo responde el programa que de verdad se ejecuta:

1. ¿Qué envía esta aplicación y a quién? (la política de privacidad dice una cosa; el binario puede hacer otra)
2. ¿Cómo salgo de aquí? (formatos y protocolos no documentados, para migrar a alternativas abiertas)
3. ¿Cómo lo mantengo sin fuentes? (el proveedor desapareció o no da soporte)

Cubre binarios nativos, JavaScript/Electron, .NET, APK, firmware y capturas de red o de procesos. Para APK solo
seguridad, ver también `mobile-security-scanner`.

## Herramienta externa: REA

[REA](https://github.com/morluto/rea) (MIT) es un MCP y CLI **locales** de ingeniería inversa. Es de terceros:
**la persona lo instala y lo aprueba**; esta skill no instala nada, no lo embebe ni lo redistribuye.

- **El agente nunca ejecuta `npx`, `npm` ni el instalador de REA.** Solo propone la orden; la ejecuta la persona.
- `npx` descarga y ejecuta código de terceros antes de leer `--dry-run`: ese flag no lo hace seguro, solo evita
  que el instalador escriba la configuración. Antes de ejecutarlo, la persona comprueba que el paquete npm
  `rea-agents` declara el repositorio `github.com/morluto/rea` (`npm view rea-agents@6.7.0 repository.url`)
  y revisa esa versión. Alternativa más estricta: clonar el repo en un tag o commit concreto.
- Orden con versión fijada (6.7.0, comprobada el 2026-10-23): `npx rea-agents@6.7.0 setup --dry-run --json`.
- Comprobar el registro: `rea doctor --client <cliente> --json`. Ayuda general: `rea --help`.
- REA no instala Java, Ghidra ni Node: también los instala la persona.
- Fijar la versión usada en el registro de la sesión (la API cambia con frecuencia). No duplicar su documentación.
- Esta skill da instrucciones; **no ejecuta análisis reales por su cuenta**.

## Puerta de autorización (antes de cualquier análisis)

Clasificar el objetivo y registrar la clase. Sin clase no hay análisis.

| Clase | Objetivo | Requisito |
|---|---|---|
| **Clase A** | Software propio o de la organización de la persona | Confirmar titularidad |
| **Clase B** | Software de terceros con autorización escrita | Doble confirmación + autorización archivada + base legal registrada |
| **Clase C** | Software de terceros dentro de un uso que la ley permite (estudiar el funcionamiento de una copia con licencia; interoperabilidad) | Doble confirmación + base legal registrada |
| **Clase D** | Cualquier otro caso | **Se rechaza.** Explicar por qué y ofrecer alternativas |

**Doble confirmación (B y C)**: pedir dos confirmaciones separadas de la persona, la primera sobre la clase y el
objetivo, la segunda sobre la base legal anotada. Registrar ambas en el informe (sección «Autorización y base legal»).
Ante duda entre dos clases, aplicar la más restrictiva.

### Base legal (pendiente de verificación con legal-compliance)

Todas las citas están **pendientes de verificación con `legal-compliance`**; el corpus consolidado no estaba disponible
al redactarlas. No se afirman como definitivas:

- Observar, estudiar y verificar el funcionamiento de un programa con licencia: art. 100.3 LPI y art. 5.3 de la
  Directiva 2009/24/CE (pendiente de verificación con legal-compliance).
- Descompilar para interoperabilidad, con condiciones: art. 100.5 y 100.6 LPI y art. 6 de la Directiva 2009/24/CE
  (pendiente de verificación con legal-compliance).
- Eludir medidas tecnológicas de protección no está protegido: art. 160 LPI (pendiente de verificación con
  legal-compliance).

## Líneas que no se cruzan

Ninguna clase de autorización las levanta. Si la tarea las exige, parar y escalar a la persona.

1. No saltar medidas de protección, licencias ni DRM.
2. No extraer credenciales ni secretos de terceros.
3. No redistribuir el código descompilado.
4. No crear malware ni exploits contra terceros.
5. No subir artefactos de nivel N3 o superior a la nube.

Pentesting de terceros queda fuera: usar `pentesting` con su propia autorización. Publicar resultados sobre software de
terceros requiere revisión legal aparte.

## Flujo por tipo de objetivo

Todos los pasos son locales. Antes: clase de la puerta registrada, artefacto en carpeta local de trabajo (N3: no sube a
la nube), versión de REA anotada.

| Objetivo | Qué responder | Enfoque |
|---|---|---|
| JavaScript / Electron | Qué endpoints llama, qué datos serializa, qué telemetría hay | Analizar el paquete de la aplicación; contrastar con tráfico observado |
| .NET | Formatos de fichero, esquema de datos, llamadas de red | Metadatos y lectura estructural del ensamblado |
| Binario nativo | Protocolos y formatos propios | Desensamblado con el motor que la persona haya instalado (Ghidra, Hopper o IDA) |
| APK | Permisos, destinos, SDK de terceros | JADX vía REA; seguridad: `mobile-security-scanner` |
| Firmware | Servicios, formato de actualización, secretos de fábrica (solo detectar, no extraer) | Extracción permitida por la clase; sin saltar protecciones |
| Captura de red / procesos | Qué sale realmente y a quién | Observación con el software en uso legítimo |

Para cada paso concreto, consultar `rea --help` y su documentación; no inventar parámetros.

## Clases de evidencia

Todo hallazgo lleva una clase. Sin clase no entra en el informe.

- **Observación**: lo visto directamente (tráfico capturado, cadena en el binario).
- **Derivación**: calculada desde observaciones con un paso reproducible.
- **Inferencia**: probable pero no comprobada; indicar qué la confirmaría.
- **Desconocido**: lo que no se pudo determinar.

Un hallazgo solo asciende de clase con evidencia nueva reproducible, nunca por insistencia. El informe incluye siempre
«Lo que no demuestra».

## Salida

Informe con `references/plantilla-informe.md`, guardado en la carpeta local de la persona. Los resultados sobre
terceros no se publican sin revisión legal. Las recomendaciones de salida (formatos, protocolos, alternativas abiertas)
son propuestas: la persona decide.

## Integración

- `sovereignty-auditor`: dimensión opcional «software opaco» (qué componentes críticos no se pueden comprobar ni sustituir).
- `/legacy-assess`: remite aquí cuando el proyecto no tiene fuentes.
- `legal-compliance`: verificación de la base legal antes de usar las clases B o C.
- `docs/rules/domain/autonomous-safety.md`: en modos autónomos esta skill no se ejecuta sin la persona.

Riesgo residual: la puerta A-D y la regla de modos autónomos viven en prosa; ningún hook las hace cumplir.

## Errores

| Situación | Acción |
|---|---|
| Objetivo no encaja en A, B ni C | Clase D: rechazar |
| Falta autorización escrita (B) | Parar; no hay análisis |
| REA no instalado | Proponer a la persona `npx rea-agents@6.7.0 setup --dry-run --json` (no ejecutarlo) y esperar |
| La tarea exige saltar una protección | Línea roja: parar y escalar |
