# Agent Code Map — Dominio

## Por que existe esta skill

Los agentes gastan entre 30-60% de sus tokens explorando la arquitectura de un proyecto al inicio de cada sesion. Esta skill genera mapas estructurales persistentes que los agentes cargan directamente, eliminando la exploracion ciega.

## Conceptos de dominio

- **ACM**: fichero markdown con estructura fija que describe entidades, dependencias y API publica de una capa del proyecto
- **INDEX.acm**: punto de entrada que lista capas disponibles con prioridad y permite carga selectiva
- **Frescura**: estado del mapa respecto al codigo fuente — fresco, obsoleto o roto
- **Carga bajo demanda**: mecanismo que permite a los agentes cargar solo las capas que necesitan
- **HCM**: gemelo narrativo del ACM orientado a humanos, mantenido por la skill human-code-map

## Reglas de negocio que implementa

- Maximo 150 lineas por fichero .acm; si crece, dividir en subdirectorios
- Hash SHA-256 del codigo fuente para detectar obsolescencia (lo calcula el agente al redactar; `scripts/refresh-agent-maps.sh` solo marca `refreshed:` y `stale-no-checkout`)
- Los .acm viven dentro del proyecto, nunca en la raiz del workspace
- Si un .acm cambia, el .hcm correspondiente se marca como stale

## Relacion con otras skills

- **Upstream**: codebase-map (mapa de dependencias que alimenta la estructura de capas)
- **Downstream**: spec-driven-development (paso inicial del pipeline SDD carga los .acm), human-code-map (gemelo narrativo)
- **Paralelo**: architecture-intelligence (detecta patrones que informan la estructura de los mapas)

## Decisiones clave

- Markdown en vez de JSON/YAML para legibilidad humana y edicion manual
- Hash por scope (no por fichero individual) para reducir overhead de verificacion
- Carga progresiva en vez de cargar completo, optimizando tokens por sesion de agente
