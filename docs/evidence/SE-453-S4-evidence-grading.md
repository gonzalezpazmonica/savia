# SE-453 S4 — Sonda de gradación de evidencia en `data-sovereignty-gate.sh`

> Sonda sin cambio de producto. Medida el 2026-10-20 sobre `origin/main` (bf186922f).

## Qué se midió

En `.claude/hooks/data-sovereignty-gate.sh` (rama BLOCK del shield), si el fichero destino es de código
(`*.py *.sh *.ps1 *.js *.mjs *.ts *.tsx *.tool`, `*/scripts/*`, `*/hooks/*`, `*/tools/*`, `*/tests/*`) y **todas** las
entidades detectadas coinciden con la lista «parece código» (línea 97), el BLOCK se rebaja a aviso (exit 0).
Se extrajo esa lista tal cual y se aplicó `grep -viE` a entidades sintéticas, una por línea.

## Resultado: hay casos

La lista es un `grep -E` no anclado por el final, así que basta que la entidad **empiece** (`^Microsoft`,
`^from `, `^HTTP`, `^API`, `^Chrome`, `^github`, `^Azure\.`, `^Dedup`...), **termine** (`8080$`, `8443$`,
`=[0-9]+$`) o **contenga** (`timeout=`, sin ancla) una palabra de código para quedar rebajada, aunque el resto sea un dato real.

| Entidad sintética (único hallazgo del shield) | Resultado |
|---|---|
| `Microsoft` + nombre de cliente + `confidential client` | rebajada a aviso |
| IP privada de la red interna terminada en `:8080` | rebajada a aviso |
| `db-prod-acme.internal:8443` | rebajada a aviso |
| `ACME_pwd=12345678` | rebajada a aviso (`=[0-9]+$`) |
| `API-prod-key-ClientX` | rebajada a aviso (`^API`) |
| `github.com/acme-corp/secret-roadmap` | rebajada a aviso (`^github`) |
| `from ` + nombre y dos apellidos | rebajada a aviso (`^from `) |
| nombre y apellido sin palabra de código | bloquea |

Control positivo: `timeout=5` (código real) se rebaja; control negativo: `Juan Perez` bloquea. Las entidades son
sintéticas; no se usó ningún dato real.

## Veredicto

**Hay un caso**: la lista puede ocultar un dato real en un fichero de código. Acotación: solo cuando el shield detecta
únicamente esas entidades y el destino es de código; el default para una entidad no reconocida sí es bloquear.

## Delta propuesto (no aplicado aquí)

Anclar con `$` o exigir forma de token de código (`^[A-Za-z_][A-Za-z0-9_.]*(\(\))?$`) además del prefijo, y no rebajar
entidades con tipo credencial/IP/URL. Requiere decisión de la operadora porque cambia el comportamiento del guard; se abre
como delta de SE-453 y no se incluye en este PR.
