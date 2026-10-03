---
layer: peripheral
name: savia-school
description: Usar cuando el workspace se adapta para un entorno educativo con estudiantes menores de edad.
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep]
metadata:
  # --- metadata.savia.* (SE-333) ---
  savia.agent: business-analyst
  savia.maturity: beta
  savia.category: governance
  savia.context: fork
  savia.priority: high
  savia.summary: "Entorno educativo seguro: alias obligatorios, cifrado AES-256 de evaluaciones, rubricas personalizables, portfolio de estudiante, derecho al olvido Art. 17 y exportacion GDPR Art. 15."
  savia.tags: "education, gdpr, minors, school, privacy, rubrics"
---

# Savia School — Entorno Educativo Seguro

Adapta pm-workspace para aulas donde los usuarios son estudiantes,
potencialmente menores de edad. Garantiza privacidad, cifrado y
cumplimiento RGPD/LOPD en todas las operaciones.

## Cuando usar

- Centros educativos que usan pm-workspace para gestionar proyectos
- Entornos con estudiantes menores de edad
- Cualquier contexto que requiera proteccion de datos de menores

## Funcionalidades principales

- **Matriculacion segura**: alias obligatorio (`[A-Za-z0-9_-]`, max 64, sin espacios ni barras), carpeta por estudiante en modo 0700
- **Evaluacion con rubricas**: niveles de logro, feedback constructivo, portfolio versionado
- **RGPD/LOPD**: Art. 15 (exportacion), Art. 17 (supresion), audit trail completo

## Scripts

- `scripts/savia-school.sh {setup|enroll|project-create|submit|evaluate|progress|export|forget}`
- `scripts/savia-school-security.sh {verify-role|check-isolation|encrypt-eval|decrypt-eval|audit-access|gdpr-consent|filter-content}`

Base de datos: `$SCHOOL_BASE/school-savia/` (por defecto `./school-savia/`; el script
de seguridad acepta `SCHOOL_ROOT` como alias historico de `SCHOOL_BASE`).
Ambos scripts operan con `umask 077`, validan alias y nombres de proyecto,
devuelven exit 2 ante uso incorrecto y exit 1 ante cualquier fallo de seguridad.

## Comandos

`/school-setup` · `/school-enroll` · `/school-project` · `/school-submit` ·
`/school-evaluate` · `/school-rubric` · `/school-progress` · `/school-portfolio` ·
`/school-diary` · `/school-analytics` · `/school-export` · `/school-forget`

## Prerequisitos

- Clave de cifrado: `$HOME/.school-keys/encryption.key` o `$SCHOOL_KEY_FILE`;
  32 bytes aleatorios en hex (`openssl rand -hex 32`), permisos 0600 y propiedad
  del usuario. Si falta, el primer cifrado la crea (directorio 0700). Si existe con
  otros permisos o formato invalido, el cifrado se niega (falla en cerrado)
- Configuracion: `references/school-safety-config.md`

## Seguridad

- Evaluaciones: AES-256-CBC con PBKDF2 (200 000 iteraciones, sal aleatoria) mas
  HMAC-SHA256 (encrypt-then-MAC). El descifrado verifica el MAC antes de
  descifrar: fichero alterado o clave distinta = exit 1 sin texto en claro.
- La clave nunca viaja en argv (`-pass file:` y HMAC por stdin). El contenido de
  la evaluacion se pasa por stdin (`encrypt-eval <alias> -`).
- `decrypt-eval` solo para el usuario que coincide con `teacher:` de
  `.school-config.md` (lo escribe `setup` con `$USER`) y solo ficheros dentro de
  `teacher/evaluations/<alias>/`. Es un guard de flujo: la barrera real es la
  clave 0600, porque `$USER` es falsificable.
- Auditoria `school-savia/.audit.log` (0600): solo fecha, usuario, accion y alias;
  nunca contenido. Acciones validadas (sin saltos de linea). Se registran
  encrypt, decrypt, gdpr-export y deletion.
- `forget` (Art. 17) y `export` (Art. 15) auditan primero; si la auditoria falla,
  no borran ni exportan. `forget` elimina `classroom/<alias>/` (incluido
  `.consent`) y `teacher/evaluations/<alias>/`; el audit log se conserva.
- `export` genera un tar.gz 0600 con rutas relativas que incluye las
  evaluaciones cifradas.
- Filtro de contenido: `SCHOOL_FORBIDDEN_KEYWORDS` (regex ERE). El valor por
  defecto solo tiene palabras en ingles: configurarlo para aulas en espanol.

- Datos de estudiantes son nivel N4b (solo profesor)
- El diario NO es accesible por padres por defecto
- Retencion cero dias tras salida (excepto incidentes: 7 anos)
- Filtro de contenido inapropiado activo por defecto
