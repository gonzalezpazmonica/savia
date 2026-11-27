# NOTAS — daemon Shield, tests Codex

Encargo: TDD cruzado para SE-442, alertas #30–32 de path-injection y acceso
sin token. Solo tests; producto, índice Git y commits intactos.

Base ejecutada: `origin/main` = `HEAD` =
`ef702d97bd029f88ba86d194e2fa7f90e03b1bfa` (2026-11-27).
No se consultó el documento de triaje situado en otro worktree:
se usó la descripción del defecto del encargo.

Reproducción desde la raíz:

```bash
bats tests/test-savia-shield-daemon-codex.bats
```

Resultado medido: **20 tests, 13 fallos esperados, 7 controles verdes**;
salida BATS 1. No hay skips ni xfail. Los fallos quedan sin neutralizar para
que la otra autora pueda comprobar su corrección contra esta suite.

| Nº | Caso (`check_case`) | En main | Evidencia |
|---|---|---|---|
| 1 | `outside_absolute` | FALLA | Abre fichero externo y devuelve ALLOW. |
| 2 | `outside_nonexistent` | FALLA | Permite destino inexistente fuera del workspace; prueba límite de prefijo compartido. |
| 3 | `outside_private_pattern` | FALLA | Patrón `config.local` permite destino externo antes de validar confinamiento. |
| 4 | `outside_trivial` | FALLA | Contenido de un carácter evita validar destino externo. |
| 5 | `symlink_file` | FALLA | Abre destino externo de enlace de fichero. |
| 6 | `symlink_directory` | FALLA | Abre destino externo mediante directorio enlazado. |
| 7 | `parent_escape` | FALLA | Lee fuera mediante ruta relativa con `..`. |
| 8 | `absolute_parent_escape` | FALLA | Lee fuera mediante ruta absoluta con `..`. |
| 9 | `path_alias_escape` | FALLA | Alias `tool_input.path` también permite lectura externa. |
| 10 | `relative_workspace` | FALLA | Lee el señuelo del cwd externo en vez del fichero del workspace. |
| 11 | `normalized_internal` | FALLA | `projects/../docs` recibe ALLOW como privado sin escanear el destino público. |
| 12 | `absolute_internal` | PASA | Permite contenido seguro y lee fichero interno existente. |
| 13 | `symlink_internal` | PASA | Un enlace interno conserva lectura y bloqueo por credencial repartida entre escrituras. |
| 14 | `relative_internal` | PASA | Ruta relativa interna segura recibe ALLOW. |
| 15 | `new_internal` | PASA | Fichero y subdirectorio interno inexistentes reciben ALLOW. |
| 16 | `no_config_no_header` | FALLA | TOKEN vacío permite ejecutar gate sin cabecera. |
| 17 | `no_config_fake_header` | FALLA | TOKEN vacío permite ejecutar gate con cabecera inventada. |
| 18 | `missing_header` | PASA | Con token configurado, rechaza cabecera ausente antes de parsear JSON. |
| 19 | `wrong_token` | PASA | Con token configurado, rechaza token incorrecto antes de parsear JSON. |
| 20 | `valid_token` | PASA | Token correcto permite parsear JSON y ejecutar gate una vez. |

Contrato elegido para la ambigüedad de «ruta relativa»: resolverla respecto
al workspace configurado (`PROJ`), aunque el cwd del servicio sea distinto.
Se aceptan destinos nuevos y symlinks cuyo destino real sigue dentro.
Las rutas que escapan deben devolver BLOCK antes de cualquier lectura o
excepción por contenido trivial/destino privado. El caso 11 exige clasificar
el destino canónico después de resolver `..`.

Para autenticación se acepta denegación HTTP 401, 403 o 503, sin ejecutar
gate ni parsear el cuerpo. No se exige un texto de error particular.

La suite importa el módulo real sin ejecutar `init()` ni `load_token()`:
no lee tokens de la persona, no descarga NER y no necesita red ni daemon vivo.
Los ficheros son sintéticos y temporales. Un audit hook de Python observa
aperturas reales, incluyendo `open` y `Path.open`; por eso devolver BLOCK
después de haber leído fuera también falla. La auditoría se desactiva y se
restaura el cwd antes de limpiar cada fixture.

Los tests HTTP invocan `H.do_POST()` con JSON en `rfile`, cabeceras y captura
de respuesta; solo se sustituye el transporte de salida. Se observa el
dispatch real a `gate`. No cubren sockets, TLS, carga del token desde disco,
startup ni carreras TOCTOU entre resolución y apertura.

Autorrevisión: los 13 rojos se ejecutaron contra el producto sin cambios.
Para cada uno de los 7 verdes se inyectó una mutación solo en memoria:
denegación de rutas seguras, respuesta cross-write sin lectura, autenticación
siempre abierta o siempre cerrada. **7/7 mutaciones detectadas** mediante
AssertionError, sin editar producto. No se usaron `! cmd` ni `|| true`.

Verificación adicional:

- `bats tests/test-shield-daemon-gate.bats`: 15/15 verdes.
- `python3 -B tests/python/test_shield_daemon_redos.py`: 3/3 verdes.
- `bash scripts/validate-ci-local.sh --quick`: 15 PASS, 0 FAIL, 2 WARN
  preexistentes (coherencia advisory y cúpula documental desactualizada).
- Auditor genérico BATS: 45/100, sin vacuidad ni aserciones débiles detectadas;
  no certificado. Sus heurísticas de flags Bash, nombres ingleses, fixtures
  shell y documento spec no reconocen este harness Python embebido. No se
  añadieron pruebas estructurales ajenas al defecto para elevar la puntuación.

No se ejecutó la suite del daemon vivo, que lee el token personal.
No se ejecutó `--clean-state` ni se leyó/actualizó el handoff privado:
acceden a otros worktrees o a ubicaciones privadas fuera del alcance del encargo.
Sin generación de artefactos, commits, push ni PR, conforme a la tarea específica.
