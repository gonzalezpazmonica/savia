#!/usr/bin/env bats
# SE-508 S1 — guard previo de efectos para tools MCP, WebFetch y WebSearch (hook de Claude Code).
# Ref: docs/specs/SE-508-mcp-webfetch-pretooluse-guard.spec.md (AC-1..AC-8c)
# Hook: .claude/hooks/mcp-effect-guard.sh · Núcleo: .claude/hooks/lib/mcp_effect_guard.py
# El remoto de referencia es un repositorio bare de fixture (file://), inyectado solo bajo bats.
# Los casos de lógica fina (formas de URL, fechas, catálogos) también están en tests/python/test_mcp_effect_guard.py.

load se508-fixture

setup() { se508_setup; }
teardown() { se508_teardown; }

SEND='mcp__claude_ai_Gmail__send_message'
GET='mcp__claude_ai_Gmail__get_message'
MERGE='mcp__github__merge_pull_request'

loosen_tree() { sed -i 's/send_message: write/send_message: read_only/' "$WS/config/mcp-effect-catalog.yaml"; }

# --- AC-1
@test "AC-1: tool read_only del catálogo → sin decisión (exit 0, sin permissionDecision)" {
  run bash "$HOOK" <<< "$(se508_payload "$GET")"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- AC-2
@test "AC-2: tool write (Gmail send_message) → ask con destino y efecto" {
  p=$(se508_payload "$SEND" '{"to":["a@x.test","b@x.test"],"bcc":["c@x.test"],"subject":"Plan de la semana"}')
  [ "$(hook_decision "$p")" = ask ]
  r=$(hook_reason "$p")
  [[ "$r" == *'Savia quiere enviar un correo a 3 personas (asunto: "Plan de la semana"). ¿Lo envío?'* ]]
  [[ "$r" == *"destino: 3 personas"* && "$r" == *"efecto: enviar un correo"* ]]
}

# --- AC-2b
@test "AC-2b: catálogo del árbol aflojado (write → read_only) y main remoto con write → ask" {
  loosen_tree
  [ "$(hook_decision "$(se508_payload "$SEND")")" = ask ]
}

@test "AC-2b: endurecer en el árbol (read_only → write) se aplica → ask" {
  sed -i 's/get_message: read_only/get_message: write/' "$WS/config/mcp-effect-catalog.yaml"
  [ "$(hook_decision "$(se508_payload "$GET")")" = ask ]
}

# --- AC-2c
@test "AC-2c: refs/remotes/origin/main reapuntada a un commit local aflojado → ask (manda ls-remote)" {
  loosen_tree
  se508_git -C "$WS" remote add origin "file://$BARE"
  se508_git -C "$WS" add -A
  se508_git -C "$WS" commit -q -m aflojado
  se508_git -C "$WS" update-ref refs/remotes/origin/main HEAD
  [ "$(hook_decision "$(se508_payload "$SEND")")" = ask ]
}

# --- AC-2e
@test "AC-2e: remote set-url origin a un bare aflojado → ask" {
  loosen_tree
  se508_publish "$TMPD/loose" "$(sed 's/send_message: write/send_message: read_only/' <<< "$SE508_CATALOG")" "$SE508_HOSTS" "$CORE_SRC"
  se508_git -C "$WS" remote add origin "file://$BARE"
  se508_git -C "$WS" remote set-url origin "file://$TMPD/loose.git"
  [ "$(hook_decision "$(se508_payload "$SEND")")" = ask ]
}

@test "AC-2e: url.<aflojado>.insteadOf=<URL de referencia> en .git/config del árbol → ask" {
  loosen_tree
  se508_publish "$TMPD/loose" "$(sed 's/send_message: write/send_message: read_only/' <<< "$SE508_CATALOG")" "$SE508_HOSTS" "$CORE_SRC"
  se508_git -C "$WS" config "url.file://$TMPD/loose.git.insteadOf" "file://$BARE"
  # control: esa regla sí reescribe la URL para un git que lee la configuración del árbol
  [ "$(git -C "$WS" ls-remote --get-url "file://$BARE")" = "file://$TMPD/loose.git" ]
  [ "$(hook_decision "$(se508_payload "$SEND")")" = ask ]
}

@test "AC-2e: la misma regla insteadOf en un ~/.gitconfig de fixture → ask" {
  loosen_tree
  se508_publish "$TMPD/loose" "$(sed 's/send_message: write/send_message: read_only/' <<< "$SE508_CATALOG")" "$SE508_HOSTS" "$CORE_SRC"
  mkdir -p "$TMPD/home"
  printf '[url "file://%s"]\n\tinsteadOf = file://%s\n' "$TMPD/loose.git" "$BARE" > "$TMPD/home/.gitconfig"
  [ "$(HOME="$TMPD/home" git ls-remote --get-url "file://$BARE")" = "file://$TMPD/loose.git" ]
  out=$(se508_payload "$SEND" | HOME="$TMPD/home" bash "$HOOK" | jq -r '.hookSpecificOutput.permissionDecision')
  [ "$out" = ask ]
}

# --- AC-2d
@test "AC-2d: ls-remote falla → read_only pasa a ask" {
  export SAVIA_MCP_GUARD_TEST_REMOTE="file://$TMPD/no-existe.git"
  [ "$(hook_decision "$(se508_payload "$GET")")" = ask ]
}

@test "AC-2d: sin remoto, ningún host de WebFetch permitido → ask" {
  export SAVIA_MCP_GUARD_TEST_REMOTE="file://$TMPD/no-existe.git" SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  [ "$(hook_decision "$(se508_payload WebFetch '{"url":"https://docs.ejemplo.org/guia"}')")" = ask ]
}

@test "AC-2d: sin remoto y SAVIA_AUTONOMOUS_RUN=1 → deny" {
  export SAVIA_MCP_GUARD_TEST_REMOTE="file://$TMPD/no-existe.git" SAVIA_AUTONOMOUS_RUN=1
  [ "$(hook_decision "$(se508_payload "$GET")")" = deny ]
}

@test "AC-2d: remoto que no contesta en 3 s → ask, sin esperar más" {
  port_file="$TMPD/port"
  python3 -c '
import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(5)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
conns = []
end = time.time() + 15
s.settimeout(0.5)
while time.time() < end:
    try: conns.append(s.accept()[0])
    except socket.timeout: pass
' "$port_file" 3>&- &
  srv=$!
  for _ in $(seq 50); do [[ -s "$port_file" ]] && break; sleep 0.1; done
  export SAVIA_MCP_GUARD_TEST_REMOTE="git://127.0.0.1:$(cat "$port_file")/savia.git"
  start=$SECONDS
  d=$(hook_decision "$(se508_payload "$GET")")
  elapsed=$((SECONDS - start))
  kill "$srv" 2>/dev/null; wait "$srv" 2>/dev/null || true
  [ "$d" = ask ]
  [ "$elapsed" -le 6 ]
}

@test "AC-2d negativo: OBSERVE_UNTIL del árbol posterior a la del remoto → manda la del remoto (enforce)" {
  sed -i 's/^OBSERVE_UNTIL = .*/OBSERVE_UNTIL = "2027-06-01"/' "$WS/.claude/hooks/lib/mcp_effect_guard.py"
  sed 's/^OBSERVE_UNTIL = .*/OBSERVE_UNTIL = "2026-11-01"/' "$CORE_SRC" > "$TMPD/early.py"
  se508_publish "$TMPD/early" "$SE508_CATALOG" "$SE508_HOSTS" "$TMPD/early.py"
  export SAVIA_MCP_GUARD_TEST_REMOTE="file://$TMPD/early.git"
  [ "$(hook_decision "$(se508_payload WebSearch '{"query":"x"}')")" = ask ]
}

# --- AC-3
@test "AC-3: mcp__github__merge_pull_request → deny citando SE-343" {
  p=$(se508_payload "$MERGE" '{"owner":"o","repo":"r","pull_number":1}')
  [ "$(hook_decision "$p")" = deny ]
  [[ "$(hook_reason "$p")" == *"SE-343"* ]]
}

# --- AC-4
@test "AC-4: tool fuera del catálogo → ask, nunca pasa" {
  p=$(se508_payload mcp__claude_ai_Nuevo__hacer_algo)
  [ "$(hook_decision "$p")" = ask ]
  [[ "$(hook_reason "$p")" == *"sin clasificar"* ]]
}

# --- AC-5
@test "AC-5: stdin vacío → ask" {
  run bash "$HOOK" < /dev/null
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$output")" = ask ]
}

@test "AC-5: JSON malformado → ask" {
  [ "$(hook_decision '{"tool_name": "mcp__x')" = ask ]
}

@test "AC-5: WebFetch sin URL → ask (también en observación)" {
  [ "$(hook_decision "$(se508_payload WebFetch '{}')")" = ask ]
}

@test "AC-5: catálogo ausente → ask para MCP, WebFetch y WebSearch, con o sin SAVIA_GATES_PIN" {
  rm "$WS/config/mcp-effect-catalog.yaml"
  for pin in "" 1; do
    export SAVIA_GATES_PIN="$pin"
    [ "$(hook_decision "$(se508_payload "$GET")")" = ask ]
    [ "$(hook_decision "$(se508_payload WebFetch '{"url":"https://docs.ejemplo.org/"}')")" = ask ]
    [ "$(hook_decision "$(se508_payload WebSearch '{"query":"x"}')")" = ask ]
  done
}

@test "AC-5: catálogo ilegible (línea fuera de formato) → ask" {
  printf 'mcp__claude_ai_Gmail__get_message: lectura\n' > "$WS/config/mcp-effect-catalog.yaml"
  [ "$(hook_decision "$(se508_payload "$GET")")" = ask ]
}

@test "AC-5: sin núcleo junto al hook → ask (el hook no deja pasar)" {
  mkdir -p "$TMPD/solo-hook"
  cp "$HOOK" "$TMPD/solo-hook/mcp-effect-guard.sh"
  out=$(se508_payload "$GET" | bash "$TMPD/solo-hook/mcp-effect-guard.sh")
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<< "$out")" = ask ]
}

# --- AC-6 (enforce: fecha posterior a OBSERVE_UNTIL)
@test "AC-6: WebFetch a host permitido sin query → pasa" {
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  [ "$(hook_decision "$(se508_payload WebFetch '{"url":"https://docs.ejemplo.org/guia/instalar"}')")" = pass ]
}

@test "AC-6: query, fragmento, ruta de 201, tramo de 65 u host no permitido → ask en enforce" {
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  long=$(printf 'a/%.0s' $(seq 100))
  seg=$(printf 'b%.0s' $(seq 65))
  for url in "https://docs.ejemplo.org/api?token=abc123" "https://docs.ejemplo.org/a#frag" \
             "https://docs.ejemplo.org/$long" "https://docs.ejemplo.org/$seg" "https://otro.test/limpio"; do
    [ "$(hook_decision "$(se508_payload WebFetch "{\"url\":\"$url\"}")")" = ask ]
  done
}

@test "AC-6 límite: ruta de 200 caracteres pasa; 201 pregunta" {
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  c=$(printf 'c%.0s' $(seq 49))
  path="/$c/$c/$c/$c"
  [ "${#path}" -eq 200 ]
  [ "$(hook_decision "$(se508_payload WebFetch "{\"url\":\"https://docs.ejemplo.org$path\"}")")" = pass ]
  [ "$(hook_decision "$(se508_payload WebFetch "{\"url\":\"https://docs.ejemplo.org${path}c\"}")")" = ask ]
}

@test "AC-6: en observación una web fuera de la lista no pregunta y deja línea would_ask" {
  [ "$(hook_decision "$(se508_payload WebFetch '{"url":"https://otro.test/x?q=1"}')")" = pass ]
  [ "$(jq -r 'select(.tool=="WebFetch") | .decision' "$SAVIA_MCP_GUARD_LOG")" = would_ask ]
}

# --- AC-7
@test "AC-7: docs.ejemplo.org no autoriza subdominio ajeno, ruta, userinfo, puerto ni http" {
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  for url in "https://docs.ejemplo.org.atacante.net/" "https://atacante.net/docs.ejemplo.org" \
             "https://docs.ejemplo.org@atacante.test/" "https://docs.ejemplo.org:8443/" "http://docs.ejemplo.org/"; do
    [ "$(hook_decision "$(se508_payload WebFetch "{\"url\":\"$url\"}")")" = ask ]
  done
}

@test "AC-7: DOCS.Ejemplo.org. (mayúsculas y punto final) sí está autorizado" {
  export SAVIA_MCP_GUARD_TEST_TODAY=2026-12-01
  [ "$(hook_decision "$(se508_payload WebFetch '{"url":"https://DOCS.Ejemplo.org./guia"}')")" = pass ]
}

# --- AC-8 (Claude Code nunca delega)
@test "AC-8: SAVIA_GATES_PIN=1 o SAVIA_MCP_GUARD=space no cambian nada en el hook: write → ask" {
  [ "$(SAVIA_GATES_PIN=1 hook_decision "$(se508_payload "$SEND")")" = ask ]
  [ "$(SAVIA_MCP_GUARD=space hook_decision "$(se508_payload "$SEND")")" = ask ]
}

@test "AC-8: merge con cualquier variable → deny" {
  [ "$(SAVIA_GATES_PIN=1 SAVIA_MCP_GUARD=space hook_decision "$(se508_payload "$MERGE")")" = deny ]
}

# --- AC-8b (sin persona)
@test "AC-8b: SAVIA_AUTONOMOUS_RUN=1 → write, no catalogada, malformado y web fuera de lista → deny antes de OBSERVE_UNTIL" {
  export SAVIA_AUTONOMOUS_RUN=1
  [ "$(hook_decision "$(se508_payload "$SEND")")" = deny ]
  [ "$(hook_decision "$(se508_payload mcp__claude_ai_Nuevo__x)")" = deny ]
  [ "$(hook_decision '{malformado')" = deny ]
  [ "$(hook_decision "$(se508_payload WebFetch '{"url":"https://otro.test/"}')")" = deny ]
}

@test "AC-8b: SAVIA_RUN_ID también cuenta como run sin persona" {
  [ "$(SAVIA_RUN_ID=r-1 hook_decision "$(se508_payload "$SEND")")" = deny ]
}

@test "AC-8b: WebSearch en un run sin persona antes de OBSERVE_UNTIL → pasa con línea de registro" {
  export SAVIA_AUTONOMOUS_RUN=1
  [ "$(hook_decision "$(se508_payload WebSearch '{"query":"algo"}')")" = pass ]
  [ "$(jq -r 'select(.tool=="WebSearch") | .decision' "$SAVIA_MCP_GUARD_LOG")" = observed ]
}

@test "AC-8b: merge sin persona deja la línea del resumen de la mañana" {
  SAVIA_AUTONOMOUS_RUN=1 hook_decision "$(se508_payload "$MERGE")" >/dev/null
  [ "$(jq -r 'select(.tool=="mcp__github__merge_pull_request") | .summary' "$SAVIA_MCP_GUARD_LOG")" = "se bloqueó un merge por MCP; los merges van con grant" ]
}

# --- AC-8c
@test "AC-8c: OBSERVE_UNTIL ayer → enforce; hoy → sigue en observación" {
  [ "$(SAVIA_MCP_GUARD_TEST_TODAY=2026-11-25 hook_decision "$(se508_payload WebSearch '{"query":"x"}')")" = ask ]
  [ "$(SAVIA_MCP_GUARD_TEST_TODAY=2026-11-24 hook_decision "$(se508_payload WebSearch '{"query":"x"}')")" = pass ]
}

@test "AC-8c: constante ilegible en el árbol → enforce" {
  sed -i 's/^OBSERVE_UNTIL = .*/OBSERVE_UNTIL = pronto/' "$WS/.claude/hooks/lib/mcp_effect_guard.py"
  [ "$(hook_decision "$(se508_payload WebSearch '{"query":"x"}')")" = ask ]
}

@test "AC-8c: main remoto sin el núcleo → usa la fecha del árbol (observación)" {
  se508_publish "$TMPD/prefusion" "$SE508_CATALOG" "$SE508_HOSTS" ""
  export SAVIA_MCP_GUARD_TEST_REMOTE="file://$TMPD/prefusion.git"
  [ "$(hook_decision "$(se508_payload WebSearch '{"query":"x"}')")" = pass ]
}

@test "AC-8c: main remoto con el núcleo pero sin la constante → enforce" {
  grep -v '^OBSERVE_UNTIL' "$CORE_SRC" > "$TMPD/sin-constante.py"
  se508_publish "$TMPD/sinconst" "$SE508_CATALOG" "$SE508_HOSTS" "$TMPD/sin-constante.py"
  export SAVIA_MCP_GUARD_TEST_REMOTE="file://$TMPD/sinconst.git"
  [ "$(hook_decision "$(se508_payload WebSearch '{"query":"x"}')")" = ask ]
}

# --- Fuera de alcance del guard
@test "una tool que no es MCP ni web no recibe decisión" {
  [ "$(hook_decision "$(se508_payload Bash '{"command":"ls"}')")" = pass ]
}
