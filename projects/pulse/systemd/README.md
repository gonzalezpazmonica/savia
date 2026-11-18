# Pulse: revisión diaria de la comprobación nocturna (SE-518 A1, S1n)

Unidad y temporizador de **ejemplo** de systemd de usuario. No se instalan solos: activarlos es un acto de la persona.

## Qué hace

`pulse nocturna` consulta, solo en lectura (`gh run list`), la última ejecución terminada de un flujo del forge. Si no es verde (fallo, cancelada, sin ejecución en 26 h, o no se puede consultar), deja una petición en «Esperan algo de ti» con el número de noches seguidas en rojo. Si es verde, `pulse status` lo dice en una línea y no hay petición. Un rojo se renueva cada día.

## Requisitos

- `gh` instalado y con sesión abierta (`gh auth status`). Pulse no guarda credenciales.
- Linux con systemd de usuario. macOS (launchd) queda para S7.

## Activar

1. Configuración fuera del repositorio, en `~/.config/pulse/nocturna.env` (permisos 600):

   ```
   PULSE_NOCTURNA_REPO=propietario/repositorio
   PULSE_NOCTURNA_FLUJO=nombre del flujo o su fichero .yml
   # opcional; por defecto main
   PULSE_NOCTURNA_RAMA=main
   ```

2. Copiar los ejemplos y ajustar la ruta de `ExecStart` a tu checkout:

   ```
   mkdir -p ~/.config/systemd/user
   cp projects/pulse/systemd/pulse-nocturna.service.example ~/.config/systemd/user/pulse-nocturna.service
   cp projects/pulse/systemd/pulse-nocturna.timer.example ~/.config/systemd/user/pulse-nocturna.timer
   ```

3. Probar una pasada a mano y activar:

   ```
   systemctl --user daemon-reload
   systemctl --user start pulse-nocturna.service
   projects/pulse/bin/pulse status
   systemctl --user enable --now pulse-nocturna.timer
   systemctl --user list-timers pulse-nocturna.timer
   ```

## Desactivar

```
systemctl --user disable --now pulse-nocturna.timer
```

## Notas

- Sin configuración, `pulse nocturna` sale con 1, no consulta nada y `pulse status` dice «sin configurar».
- La racha cuenta jornadas UTC con una pasada en rojo; dos pasadas el mismo día no suman. Si el equipo estuvo apagado varios días, esos días no cuentan. Límite aceptado: una pasada a las 23:5x UTC y otra a las 00:0x UTC del día siguiente suman dos noches aunque solo haya habido una ejecución; programa el temporizador lejos de la medianoche UTC.
- Solo cuentan las ejecuciones de la rama vigilada (`PULSE_NOCTURNA_RAMA`, por defecto `main`). Una ejecución manual en otra rama, aunque sea más reciente y verde, no tapa el rojo. Una ejecución manual en la rama vigilada sí cuenta: es una ejecución real de esa rama.
- Si la última pasada de Pulse tiene más de 26 h, `pulse status` no dice «bien»: dice que no sabe cómo está ahora.
