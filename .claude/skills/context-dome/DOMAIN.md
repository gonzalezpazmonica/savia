# Context Dome -- Dominio

## Por que existe esta skill

El conocimiento de un modulo no vive solo en el codigo. Vive en la
cabeza de quien lo escribio: por que se tomo esa decision de diseno,
que intentos fallaron antes, que falla si cambias esa linea, como
arrancarlo en local cuando nada funciona.

Cuando esa persona se va, ese conocimiento desaparece. Un CONTEXT_DOME.md
bien generado reduce ese riesgo capturando lo que el historial git si
puede revelar, y marcando explicitamente lo que necesita documentacion
manual.

## Que es una cupula de contexto

Un Module Passport (terminologia de Google SRE) con enfoque en
conocimiento tacito:

- **No es** un README. Un README explica que hace el modulo.
  Un Context Dome explica **por que** hace lo que hace y **como**
  sobrevivir cuando algo falla.

- **No es** una ADR. Una ADR documenta una decision. Un Context Dome
  agrega multiples decisiones mas el contexto operativo.

- **Es** el artefacto que el nuevo dev necesita antes de su primera
  semana tocando ese modulo.

## Patron Module Passport (Google)

Google SRE documentacion interna (Site Reliability Engineering, cap. 10)
describe el concepto de "module passport":

> "Every service should have a document that answers: what does it do,
> who owns it, how do you run it, and what are the known failure modes."

Context Dome implementa este patron con generacion automatica para
reducir el coste de crearlo (barrrera principal a la documentacion).

## Cuando una cupula es "buena"

Una CONTEXT_DOME.md es util si un dev que nunca ha tocado el modulo puede:

1. Entender el proposito en menos de 2 minutos
2. Arrancar el modulo en local siguiendo el runbook
3. Identificar las 3 decisiones no obvias que afectarian su trabajo
4. Saber a quien preguntar si algo no funciona

### Senales de cupula pobre
- Proposito: "[sin descripcion detectada]" -- documentar manualmente
- Runbook confidence: low -- el script no encontro comandos
- Decisiones: "[sin decisiones documentadas]" -- commits sin contexto
- Owners: solo un dev -- el BF=1 que motivo la generacion

## Limites: que no captura

Una cupula de contexto NO sustituye:

1. **Conocimiento organizativo**: quien aprueba los despliegues, quien
   tiene las credenciales de produccion, el numero del soporte del
   proveedor. Ver `org-stakeholder-mapper` skill.

2. **Conocimiento de negocio**: por que el cliente quiere esa feature,
   cual es la regla de negocio detras de ese calculo. Ver CONTEXT.md
   de `ubiquitous-language` skill.

3. **Experiencia acumulada**: los edge cases que solo se ven con anos.
   La cupula puede listar HACK: y FIXME: del historial, pero no
   puede transferir intuicion.

4. **Conocimiento futuro**: decisiones que aun no se han tomado. La
   cupula es una fotografia, no una prediccion.

## Ciclo de vida de una cupula

```
Generacion automatica (BF <= 2)
    |
    v
Revision manual por knowledge owner (runbook, proposito)
    |
    v
Validacion por segundo dev (puede arrancar el modulo?)
    |
    v
Mantenimiento: regenerar tras cambios grandes (BF scan mensual)
    |
    v
Deprecacion: modulo eliminado o completamente reescrito
```

## Consideraciones de PII

El CONTEXT_DOME.md lista knowledge owners por email git. Aplican
las mismas guias que en bus-factor-analysis/DOMAIN.md:

- No usar como metrica de rendimiento
- El archivo vive en el repo del proyecto (no en pm-workspace)
- Si el repo es publico, generar con `--redact-owners` (owners sin dominio)
- Nunca se mezcla el scan de otro proyecto (aislamiento N4) ni commits de
  ramas sin integrar
