---
context_tier: L3
token_budget: 1500
---

# Merge bajo permiso expreso — referencia de la firma de la operadora

> Detalle de `autonomous-safety-merge-grant.md` (SE-343), movido aquí para
> mantener esa regla bajo el cap de 150 líneas. Misma doctrina, mismo peso.

## Firma de la operadora (LAW-HUMAN-002, firma asimétrica)

Pedir el grant no basta y Savia no puede emitirlo sola:

1. `operator-grant.sh grant --scope merge --resource pr:<n> --context "..."`
   solo deja una petición canónica en `~/.savia/grants/merge.request` y la
   imprime (exit 4). Lleva id aleatorio, `grantor` (principal), `scope`,
   `repo` (remoto `origin` normalizado, `host/owner/name`), `resource`,
   `head_sha` (la cabeza del PR, `headRefOid`, leída con `gh` al pedirlo) y
   vigencia (`issued_epoch`, `expires_epoch`). Sin remoto identificable o sin
   poder leer la cabeza, exit 2.
2. La operadora la firma con su clave ed25519 **privada**, que vive en su móvil
   o en Savia Space y nunca en el equipo de los agentes:
   `ssh-keygen -Y sign -f <clave> -n savia-operator-grant <petición>`.
3. `operator-grant.sh grant --scope merge --signature <petición>.sig` (o
   `--signature -` pegando la firma) verifica e incorpora la firma.

`check --scope merge --resource pr:<n>` verifica cada vez, en el punto de uso,
cada campo firmado y la firma con `ssh-keygen -Y verify` contra
`config/operator-grant-signers` **de `origin/main`** (formato `allowed_signers`, identidad =
`grantor`, namespace `savia-operator-grant`). Un `merge.json` escrito a mano,
alterado, firmado por otra clave, con otro namespace, de otra petición, de otro
repositorio, PR o scope, caducado, consumido o revocado no vale. Sin `--resource`, sin
ninguna clave en ese fichero o sin `ssh-keygen`, ningún grant de merge es válido.

`consume` y `revoke` apuntan el id en `~/.savia/grants/merge.spent` (`revoke`,
también el de la petición pendiente); `check` y la incorporación de la firma
rechazan esos ids, así que restaurar una copia guardada del grant o de la
petición no la revive. El verificador corre con `python3 -I` y un PATH fijo de
sistema, y `python3` y `git` se invocan por ruta absoluta: ni
`PYTHONPATH`/`sitecustomize`, ni un `ssh-keygen` falso en el PATH, ni una
función exportada (`export -f python3`) lo sustituyen. Límite: quien controla
el entorno del proceso (`BASH_ENV`, funciones exportadas con el nombre de
`exit` o `builtin`) controla el código de salida de cualquier script Bash; el
exit de `check` no es frontera frente a un llamante hostil (ver abajo).

### Qué prueba la firma y qué no

Una firma válida prueba que se usó la clave privada registrada, **no** que
hubiera una persona delante. La garantía de presencia humana viene de la
ceremonia: la clave privada vive solo en el móvil de la operadora (o en Savia
Space), con frase de paso, y nunca en el equipo de los agentes. Si la clave
saliera de ahí, la firma dejaría de probar nada sobre ella.

### Alta de la clave (procedimiento manual de la operadora)

1. En el móvil (p. ej. Termux) o en Savia Space:
   `ssh-keygen -t ed25519 -f ~/.ssh/savia-grant -C savia-grant`, con frase de paso.
2. Copiar SOLO la pública (`savia-grant.pub`) y añadir una línea a
   `config/operator-grant-signers`:
   `<active_slug> namespaces="savia-operator-grant" ssh-ed25519 AAAA...`.
3. Hacerlo por PR propia y mergearla ella: el hook `operator-grant.sh guard`
   veta a los agentes editar ese fichero.
4. Rotación o pérdida del móvil: quitar la línea antigua y añadir la nueva por
   el mismo camino. Quitarla invalida al instante los grants ya firmados.

Límite: el guard ve el texto de la orden (resuelve comillas, barras, ANSI-C
`$'…'`, `$"…"`, continuaciones, escapes de printf, globs, llaves y secuencias
`{a..z}`, también desde los destinos de `cd`/`pushd`/`-C`), no lo que
ejecuta un script escrito antes, una variable que compone el nombre ni un cambio
de rama. En Bash veta cualquier mención del nombre exacto, también las lecturas
(`git status -- …`): para leerlo, la herramienta Read.

Qué protege y qué no:

- `check` y la incorporación de la firma verifican contra la raíz de confianza
  de **`origin/main`** (`git cat-file blob refs/remotes/origin/main:config/operator-grant-signers`
  a un temporal), nunca contra la copia de trabajo ni la rama: una rama que
  añade su propia clave no se autoriza a sí misma. Sin `origin/main` o sin el
  fichero en ella, ningún grant de merge vale.
- `push-pr.sh --merge` rechaza siempre un PR que modifica
  `config/operator-grant-signers`, según el diff local contra `origin/main` o
  según la lista de ficheros del PR en GitHub (basta una; si alguna no se puede
  leer, no hay merge). Ese PR lo mergea la operadora a mano.
- `risk-tier.py` clasifica `config/operator-grant-signers`,
  `scripts/operator-grant.sh` y `scripts/push-pr.sh` como gobernanza (tier 4):
  `push-pr.sh --merge` rechaza tier ≥ 3 y `merge-sprint.sh` no admite tier 4.
- Un grant de merge no puede durar más de 24 h (`--ttl-hours` solo dígitos, y
  `check` rechaza vigencias mayores aunque estén firmadas).

Límites que siguen: el verificador (`operator-grant.sh`, `push-pr.sh`,
`risk-tier.py`) es código de la rama que se ejecuta, así que una rama que lo
reescriba se salta todo lo anterior si alguien lo ejecuta desde ella; y quien
controla el repositorio local puede mover `refs/remotes/origin/main`. La lista
de ficheros de GitHub (`gh pr view --json files`) puede quedarse en los
primeros 100; el diff local cubre el resto. Estos controles locales son
defensa en profundidad. La frontera real es del lado de GitHub: la
protección de rama o ruleset de `main` que exige la revisión y el merge de la
operadora, y que el token de los agentes no pueda saltársela. Es un requisito,
no algo que este script garantice.

El libro `merge.spent` es local y su ruta admite `SAVIA_GRANTS_DIR` (lo usan
los tests): quien pueda borrarlo o redirigirlo y conserve una copia podría
reusar el grant, pero solo para el mismo repositorio y PR (van firmados) y
dentro de su vigencia.
