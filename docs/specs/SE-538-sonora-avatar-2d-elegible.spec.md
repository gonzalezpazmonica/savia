---
status: PROPOSED
priority: P2
developer_type: agent-single
created: 2026-11-26
author: Savia
phase: D
risk: L2
human_surface: true
related_specs: [SE-537, SE-432, SE-312]
origin: "Propuesta de la operadora del 2026-11-26 sobre Savia Sonora (en Savia Labs), sección del avatar 2D. Escenas confirmadas por pregunta interactiva el 2026-11-26."
timeline:
  - from: "2026-11-26"
    learned: "2026-11-26"
    value: "PROPOSED"
    source: "orquestadora; escenas confirmadas por la operadora en pregunta interactiva del 2026-11-26"
---
# SE-538 — Avatar 2D elegible y desactivable en Sonora

## Problema (verificado en origin/main 4104a2bd1, 2026-11-26)

1. **Sonora no tiene avatar.** Sí tiene la base: `pages/Popup.tsx` maneja estados (`idle`, `recording`, `processing`…), barras por amplitud (`:110,225`) y movimiento reducido, y el bus `ui_event_bridge.py` → `useBackendEvent.ts` lleva eventos del backend a la vista.
2. **La amplitud que hay es la del micrófono** (`audio.py:30`), no la de la voz reproducida. Una boca que se mueve con el micrófono se mueve cuando habla la persona, no cuando habla Savia.
3. **Hay dos sitios decidiendo el avatar.** SE-432 tiene abierta la D2 («avatar de Savia (buhita) en el producto») para Savia Space. Si cada superficie dibuja el suyo, Savia acaba con dos caras distintas.

## Lo que he entendido

### Qué ve la persona hoy

En Sonora, una ventana con barras que se mueven al grabar. Savia no tiene cara.

### Qué verá la persona con esta spec

Una cara 2D sencilla, no realista, encima de los subtítulos de la conversación (SE-537). La cara indica si Savia escucha, piensa o habla, y solo mueve la boca cuando suena la voz. Hay al menos dos estilos para elegir y una opción para quitarla.

### Escenas

1. **Habla.** Savia contesta. La boca se mueve al ritmo de la voz que suena y se para cuando la voz se calla, también si la persona la interrumpe.
2. **Escucha y piensa.** Con el atajo pulsado, la cara muestra que escucha. Al soltarlo, muestra que piensa hasta que llega la primera frase.
3. **Elige o quita.** En ajustes, la persona elige entre al menos dos estilos o «sin cara». Sin cara, la conversación sigue igual: el texto y el indicador de trabajo no cambian.
4. **Movimiento reducido.** Si el sistema pide reducir el movimiento, la boca no se anima. El estado se indica con un cambio estático (color o forma).

### Palabras de la persona

«Analiza, specs y roadmap de Savia Sonora esta semana. Dedica todos los recursos posibles.» Es el texto literal de la operadora del 2026-11-26. Su propuesta pide que el primer avatar sea exclusivamente 2D, elegible y desactivable. La orquestadora redactó las escenas a partir de ella.

### Qué SÍ será

- Una cara 2D vectorial (SVG o canvas), dibujada en local, sin recursos de red.
- Al menos dos estilos predefinidos más «sin cara».
- Una boca que se mueve por la amplitud (RMS) **del audio que se reproduce**, ligada a la época de voz de SE-537.
- Estados visibles: en reposo, escucha, piensa, habla, sin red.
- Respeto de `prefers-reduced-motion`.
- La misma definición de cara para Sonora y para Space, si la persona lo decide así en la D2 de SE-432 (ver D3).

### Qué NO será

- Ni 3D, ni realismo, ni rostro de una persona real.
- Ni visemas ni lectura de fonemas en este paso: solo la amplitud.
- Ni librerías que carguen nada de una CDN o de la red mientras se ejecuta.
- Ninguna dependencia de la conversación respecto a la cara.

### Confirmación

- fecha: 2026-11-26
- respuesta: «Sí, es eso». Es la respuesta de la operadora, por pregunta interactiva, a las escenas de Sonora. Su escena 3 es la cara: «una cara 2D sencilla, no realista, que solo mueve la boca cuando suena la voz y que indica si escucha o habla. Puedes elegir entre al menos dos estilos o quitarla, y la conversación sigue igual». Las escenas 1, 2 y 4 de esta sección la desglosan. Las escenas 2 («piensa») y 4 (movimiento reducido) amplían lo confirmado y se enseñan en el prototipo para confirmarlas allí.

## Slice S0 — Prototipo navegable

prototipo: página HTML local sin red, con dos estilos y «sin cara», botones para pasar por los estados escucha, piensa, habla, voz callada con el trabajo en marcha y sin red, una boca que se mueve con audio sintético y un interruptor de movimiento reducido. Se entrega a la persona como página privada para que la pruebe en su dispositivo.

### Confirmación del prototipo

- fecha: pendiente
- respuesta: pendiente

## Qué decide esta spec

### D1 — Fuente de la amplitud

El `tts_worker` de SE-537 publica un evento `speech-level` con `{epoch, seq, rms, t}` cada 30–50 ms **del bloque que está sonando**. La vista ignora los eventos de una época anterior. Cuando llega `speech-interrupted`, la boca se cierra en el mismo fotograma.

Precisiones de la revisión documental de Codex del 2026-11-26 (Labs, L12):

- El nivel se calcula sobre el PCM **que se envía al dispositivo**, después de la ganancia y del silencio de la aplicación. No se usa el que solo está generado o en cola.
- En estéreo se suman las energías de los canales: `sqrt(Σx²/(C·N))`. Así dos canales en contrafase no se anulan.
- Si la entrada no es válida (NaN, Inf, formato desconocido), la boca queda neutral y se escribe un diagnóstico. El renderer nunca recibe NaN.
- El cálculo se acumula en el callback de audio, pero el evento se publica fuera de él: dentro no se serializa JSON ni se hace E/S.
- Al recuperar una ventana oculta no se reproducen fotogramas atrasados.

### D2 — Estilos

Un estilo es un JSON con formas y colores y sin código. Los dos primeros son una buhita esquemática y un círculo con boca. Los colores salen de los tokens del tema (claro, oscuro o sistema): ninguno se impone.

### D3 — Una sola cara para Savia

Esta spec propone cerrar la D2 de SE-432 con la misma definición de estilos, para que Space y Sonora no dibujen dos caras distintas. Lo decide la persona; mientras no lo haga, la cara vive solo en Sonora.

## Slices

| Slice | Contenido | Tier | Depende de |
|---|---|---|---|
| S0 | Prototipo navegable y confirmación | 1 | — |
| S1 | Componente `SaviaFace` con estados, dos estilos, «sin cara» y movimiento reducido, alimentado por los eventos de estado | 1 | S0 confirmado; SE-537 S1 |
| S2 | Boca por `speech-level` ligada a la época | 2 | SE-537 S2 |

### Criterios de aceptación

- [ ] S1: con «sin cara», la vista de conversación muestra el mismo texto y el mismo indicador que con cara (test de componente).
- [ ] S1: con `prefers-reduced-motion`, no hay animación CSS ni JS en la boca (test).
- [ ] S1: el bundle no hace peticiones de red al montar la cara (test con `fetch` y `XMLHttpRequest` bloqueados).
- [ ] S2: un `speech-level` de una época anterior no mueve la boca (test).
- [ ] S2: tras `speech-interrupted`, la boca queda cerrada en ≤ 1 fotograma (test con reloj falso).
- [ ] S2: con amplitud de micrófono y sin voz reproducida, la boca no se mueve (test negativo).
- [ ] S2: un PCM estéreo en contrafase produce un nivel distinto de cero, y PCM vacío, NaN o Inf dejan la boca neutral sin propagar NaN (tests).
- [ ] S2: un activo de estilo que intenta cargar una URL externa se rechaza y la cara cae al estilo por defecto (test negativo).

## Fuera de alcance

Visemas, 3D, expresiones emocionales, cara en Space (eso depende de la D2 de SE-432) y avatares con la imagen de una persona.

## Preguntas abiertas

1. ¿La cara de Savia es la misma en Space y en Sonora? Es la D2 de SE-432 y la decide la persona.
2. ¿Hay que medir la latencia del evento `speech-level` en Qt WebEngine en el Mac antes de S2?

## Riesgos

- **Boca desfasada de la voz.** Si el evento llega tarde respecto al altavoz, la boca se ve rara. *Mitigación:* se mide en el Mac en S2. Si el desfase pasa de 100 ms, se adelanta el evento con la latencia de salida medida.
- **Cara que distrae.** *Mitigación:* «sin cara» está a un clic y se recuerda.

## Aprobación

- estado: PROPOSED. Confirmar las escenas no aprueba la spec.
