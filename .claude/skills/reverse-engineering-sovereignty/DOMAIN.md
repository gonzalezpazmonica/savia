# reverse-engineering-sovereignty — Dominio

## Por qué existe esta skill

La soberanía tecnológica de una persona, una administración, una comunidad o un pueblo empieza por poder comprobar qué
hace el software del que depende y por poder salir de él. Cuando no hay fuentes ni documentación fiable, la única
respuesta está en el programa que se ejecuta. Esta skill guía esa comprobación con una herramienta externa (REA) bajo una
puerta de autorización y unas líneas que no se cruzan. Su fin es comprobar y poder salir, nunca atacar.

## Conceptos de dominio

- **Software opaco**: componente del que se depende y cuyo comportamiento real no se puede comprobar con fuentes o
  documentación (binario cerrado, aplicación empaquetada, firmware).
- **Puerta de autorización A-D**: clasificación previa del objetivo; sin clase no hay análisis y la clase D se rechaza.
- **Clases de evidencia**: observación, derivación, inferencia y desconocido; lo no examinado es desconocido, no ausencia.
- **Plan de salida**: formatos, protocolos y alternativas abiertas que permiten migrar.

## Reglas de negocio que implementa

- SE-455 (spec aprobada el 2026-10-23).
- Principios éticos de Savia (`docs/rules/domain/savia-ethical-principles.md`): la herramienta sirve a la dignidad y la
  autonomía, no al daño.
- Soberanía del dato: los artefactos N3 o superiores nunca salen a la nube.
- Autonomous safety: en modo autónomo la skill no se ejecuta sin la persona.

## Relación con otras skills

- **Upstream**: `sovereignty-auditor` (la dimensión «software opaco» señala qué componentes comprobar).
- **Upstream**: `/legacy-assess` (remite aquí cuando no hay fuentes).
- **Paralelo**: `mobile-security-scanner` (seguridad de APK), `pentesting` (pruebas de seguridad con su propia autorización).
- **Control**: `legal-compliance` (verificación de la base legal de las clases B y C).

## Decisiones clave

- REA es externo y lo instala la persona: Savia no instala, no embebe ni redistribuye motores de terceros.
- Doble confirmación en las clases B y C, y la clase más restrictiva ante la duda.
- Las citas legales quedan marcadas como pendientes de verificación hasta que `legal-compliance` las contraste.
- La skill da instrucciones y no ejecuta análisis por su cuenta: el resultado es un informe con «Lo que no demuestra».
