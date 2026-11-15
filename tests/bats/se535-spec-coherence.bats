#!/usr/bin/env bats
# SE-535 — coherencia de la spec: cliente externo del puente con alcance solo de conversación.
# Fija que la spec no pierda sin querer sus garantías (lista blanca, solo lectura, sin contenido en
# registros, topes, escucha concreta con TLS, criterio de abandono) y que el repo público quede limpio.
# Aviso: comprueba texto, no el puente (la spec no cambia código). Cada comprobación se ejecuta también
# sobre una copia mutada y debe fallar.

set -o pipefail

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SPEC="$REPO_ROOT/docs/specs/SE-535-cliente-externo-solo-conversacion.spec.md"
STATE="$REPO_ROOT/docs/propuestas/planning.d/SE-535.json"

# Huellas genéricas de datos privados (rutas personales, correos, direcciones de VPN de malla,
# interfaces y carpetas de estado local), armadas por trozos para que este fichero no contenga
# los literales que busca. Sin nombres de personas ni de organizaciones: el patrón es genérico.
priv_re() {
  printf '%s' "\\.sa""via/|inten""sivo|Savia""Labs" \
    "|[A-Za-z0-9._-]+@[A-Za-z0-9-]+\\.[a-z]{2,}|/ho""me/[a-z]|/Us""ers/[a-z]" \
    "|100\\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\\.[0-9]+\\.[0-9]+|tail""scale0"
}

check() {  # check <fichero>: 0 si la spec es coherente
  local f="$1"
  [ -s "$f" ] || { echo "spec vacía"; return 1; }
  grep -q '^status: PROPOSED$' "$f" || { echo "status"; return 1; }
  grep -q '^human_surface: true$' "$f" || { echo "human_surface"; return 1; }
  grep -q '^# SE-535 — ' "$f" || { echo "título"; return 1; }
  # Puerta de comprensión: secciones y confirmaciones pendientes (no inventadas).
  local s
  for s in '## Lo que he entendido' '### Escenas' '### Palabras de la persona' '### Qué SÍ será' \
           '### Qué NO será' '### Confirmación' '## Slice S0 — Prototipo navegable' '### Confirmación del prototipo'; do
    grep -qxF "$s" "$f" || { echo "falta sección: $s"; return 1; }
  done
  [ "$(grep -c '^- respuesta: pendiente' "$f")" -eq 2 ] || { echo "confirmaciones no pendientes"; return 1; }
  # De 3 a 5 escenas numeradas.
  local n
  n=$(awk '/^### Escenas/{on=1;next} /^### /{on=0} on && /^[0-9]+\. \*\*/{c++} END{print c+0}' "$f")
  [ "$n" -ge 3 ] && [ "$n" -le 5 ] || { echo "escenas: $n"; return 1; }
  # Slices y tiers.
  grep -qE '^\| S1 \|.*\| 3 ' "$f" || { echo "tier S1"; return 1; }
  grep -qE '^\| S2 \|.*\| 2 \|$' "$f" || { echo "tier S2"; return 1; }
  # Garantías de S1.
  grep -q 'por lista blanca: `POST /chat` y `GET /health`' "$f" || { echo "lista blanca"; return 1; }
  grep -q 'ruta futura responde 403' "$f" || { echo "rutas futuras"; return 1; }
  grep -q 'se muestra una sola vez y se guarda solo su hash' "$f" || { echo "token una vez"; return 1; }
  grep -q 'solo con herramientas de lectura (`Read`, `Grep`, `Glob`)' "$f" || { echo "herramientas"; return 1; }
  grep -q 'sin servidores MCP' "$f" || { echo "sin MCP"; return 1; }
  grep -q 'solo los ficheros versionados' "$f" || { echo "copia versionada"; return 1; }
  grep -q 'sin enlaces simbólicos que apunten fuera de la copia' "$f" || { echo "enlaces"; return 1; }
  grep -q '^## Evidencia de factibilidad$' "$f" || { echo "factibilidad"; return 1; }
  grep -q 'Nunca el contenido' "$f" || { echo "registro sin contenido"; return 1; }
  grep -q '429 con `retry_after_s`' "$f" || { echo "topes"; return 1; }
  grep -q 'dirección de escucha es comodín' "$f" || { echo "escucha"; return 1; }
  grep -q 'o si no hay TLS' "$f" || { echo "TLS"; return 1; }
  grep -q 'con el CLI real, no simulado' "$f" || { echo "pruebas reales"; return 1; }
  # Doce AC en S1 y cinco en S2, numerados sin huecos.
  [ "$(grep -oE '^- AC-1\.[0-9]+' "$f" | paste -sd,)" = "$(printf -- '- AC-1.%s\n' 1 2 3 4 5 6 7 8 9 10 11 12 | paste -sd,)" ] \
    || { echo "AC de S1"; return 1; }
  [ "$(grep -oE '^- AC-2\.[0-9]+' "$f" | paste -sd,)" = "- AC-2.1,- AC-2.2,- AC-2.3,- AC-2.4,- AC-2.5" ] \
    || { echo "AC de S2"; return 1; }
  grep -q '^## Criterio de abandono$' "$f" || { echo "abandono"; return 1; }
  grep -q 'barrera solo en el prompt' "$f" || { echo "abandono sin prompt"; return 1; }
  # Decisiones para la operadora y criterio de niveles.
  for s in '**D1 ' '**D2 ' '**D3 ' '**D4 '; do grep -qF -- "- $s" "$f" || { echo "falta $s"; return 1; }; done
  grep -q 'Nada N2, N3, N4 ni N4b' "$f" || { echo "niveles"; return 1; }
  grep -q 'No toca el servidor de cúpulas' "$f" || { echo "cúpulas"; return 1; }
  # Repo público limpio.
  if grep -qiE "$(priv_re)" "$f"; then echo "dato privado"; return 1; fi
  return 0
}

mutate() {  # mutate <sed-expr>: copia mutada de la spec
  local out="$BATS_TEST_TMPDIR/mut.md"
  sed -e "$1" "$SPEC" > "$out"
  echo "$out"
}

@test "la spec es coherente" {
  run check "$SPEC"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "planning y spec coinciden en id, estado y evidencia" {
  run python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["id"]=="SE-535" and d["status"]=="PROPOSED" and d["evidence"].endswith("SE-535-cliente-externo-solo-conversacion.spec.md"), d' "$STATE"
  [ "$status" -eq 0 ]
  [ -f "$REPO_ROOT/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["evidence"])' "$STATE")" ]
}

@test "negativo: estado APPROVED sin aprobación falla" {
  run check "$(mutate 's/^status: PROPOSED$/status: APPROVED/')"
  [ "$status" -ne 0 ]; [[ "$output" == *status* ]]
}

@test "negativo: confirmación inventada falla" {
  run check "$(mutate '0,/^- respuesta: pendiente/s//- respuesta: «sí»/')"
  [ "$status" -ne 0 ]; [[ "$output" == *confirmaciones* ]]
}

@test "negativo: ampliar la lista blanca falla" {
  run check "$(mutate 's/`POST \/chat` y `GET \/health`/`POST \/chat`, `GET \/files` y `GET \/health`/')"
  [ "$status" -ne 0 ]; [[ "$output" == *"lista blanca"* ]]
}

@test "negativo: dar Bash a la conversación falla" {
  run check "$(mutate 's/(`Read`, `Grep`, `Glob`)/(`Read`, `Grep`, `Glob`, `Bash`)/')"
  [ "$status" -ne 0 ]; [[ "$output" == *herramientas* ]]
}

@test "negativo: guardar contenido en el registro falla" {
  run check "$(mutate 's/Nunca el contenido/Con el contenido/')"
  [ "$status" -ne 0 ]; [[ "$output" == *registro* ]]
}

@test "negativo: quitar la negativa sin TLS falla" {
  run check "$(mutate 's/ o si no hay TLS//')"
  [ "$status" -ne 0 ]; [[ "$output" == *TLS* ]]
}

@test "negativo: permitir enlaces que salen de la copia falla" {
  run check "$(mutate 's/ y sin enlaces simbólicos que apunten fuera de la copia//')"
  [ "$status" -ne 0 ]; [[ "$output" == *enlaces* ]]
}

@test "negativo: perder un AC falla" {
  run check "$(mutate '/^- AC-1\.7 /d')"
  [ "$status" -ne 0 ]; [[ "$output" == *"AC de S1"* ]]
}

@test "negativo: seis escenas falla (límite superior)" {
  run check "$(mutate 's/^5\. \*\*Lo retiras\.\*\*/5. **Lo retiras.** x\n6. **Otra.** y/')"
  [ "$status" -ne 0 ]; [[ "$output" == *escenas* ]]
}

@test "negativo: una dirección de VPN real falla" {
  local ip="1""00.101.102.103"  # inventada, del rango de las VPN tipo malla; armada por trozos
  run check "$(mutate "s/escucha solo en la dirección que se le indica/escucha en $ip/")"
  [ "$status" -ne 0 ]; [[ "$output" == *privado* ]]
}

@test "negativo: una ruta personal falla" {
  run check "$(mutate "s|ficheros versionados del repo|ficheros de /ho""me/alguien/repo|")"
  [ "$status" -ne 0 ]; [[ "$output" == *privado* ]]
}

@test "límite: spec inexistente falla cerrado" {
  run check "$BATS_TEST_TMPDIR/no-existe.md"
  [ "$status" -ne 0 ]
}
