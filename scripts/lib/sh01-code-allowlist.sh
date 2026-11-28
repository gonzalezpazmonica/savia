#!/usr/bin/env bash
# sh01-code-allowlist.sh — SPEC-SH01 / SE-453 S6: ¿todas las entidades del shield son código?
# Lo usa data-sovereignty-gate.sh para rebajar un BLOCK a aviso en ficheros de código.
#
# Antes (hasta SE-453 S6) la lista era un `grep -viE` sin ancla final: una entidad que solo EMPEZABA
# (Microsoft…, from …, HTTP…), TERMINABA (…:8080, …=123) o CONTENÍA (timeout=) una palabra de código
# se rebajaba aunque el resto fuera un dato real (docs/evidence/SE-453-S4-evidence-grading.md).
# Ahora cada patrón casa con la entidad ENTERA (grep -x), distingue mayúsculas (sin -i) y no deja
# sufijos abiertos tras palabras cortas (Restrepo ya no es REST…, ni Apiano API…). Además, fail-closed:
#   - toda entidad debe tener un tipo de nombre (NER); credencial/IP/URL/email/sin tipo → nunca se rebaja;
#   - un clave=valor cuya clave parece secreto (pwd, pass, secret, token, key, auth, cred) → nunca;
#   - un clave=número solo se rebaja con una clave de la lista cerrada _K (dni=, pin=, cvv= → nunca);
#   - una entidad con salto de línea o vacía → nunca.

# Tipos NER de nombre (mismos que el relajo N3/N4 del hook, más DATE_TIME de Presidio).
SH01_NAME_TYPES='PERSON|PERSON_ES|ORG|ORGANIZATION|LOCATION|GPE|DATE|TIME|DATE_TIME|NRP|EVENT|PRODUCT|WORK_OF_ART|MISC|LAW|LANGUAGE|ORDINAL|CARDINAL|QUANTITY|PERCENT|MONEY'

# Piezas de forma. Ninguna deja un sufijo abierto tras una palabra corta: un sufijo es un tramo
# CamelCase o snake_case que empieza por mayúscula, dígito o «_» (DedupKey sí, Dedupova no), y un
# segmento con punto es de código (minúscula inicial, sigla o CamelCase de dos tramos) o de la lista
# cerrada _NS. Un apellido («Garcia») es una palabra capitalizada suelta y no casa con ninguno.
_L='[a-z_][A-Za-z0-9_]*'                     # identificador con minúscula inicial o «_»
_C='([A-Z0-9_][A-Za-z0-9_]*)?'               # sufijo CamelCase/snake, nunca minúsculas sueltas
_DL='(\.[a-z_][A-Za-z0-9_]*)*'               # segmentos de módulo: .parse, .path, .goto
_NS='VSTS|Common|Scheduling|Effort|Priority|State|Title|Tags|Reason|Identity|Core|Storage|Blob|Web|Text|IO|Net|Http|Json|Linq|Collections|Generic|Threading|Tasks|Data|Security|Cloud|Auth|Graph|Id'
_DS="(\\.(${_L}|[A-Z][A-Z0-9]+|[A-Z][a-z0-9]+([A-Z][a-z0-9]*)+|${_NS}))*"   # segmentos de espacio de nombres
# Claves de kwargs numéricos: lista cerrada.
_K='timeout|retries|max_retries|default|port|limit|count|size|depth|level|verbose|workers|interval|delay|attempts|max|min|step|width|height|indent|maxsplit|offset|page|per_page|batch_size|n|i|j|k'
# Sufijos técnicos admitidos tras una sigla (HTTPError, APIKey; nunca Httpson ni Restrepo).
_AS='Error|Exception|Client|Server|Request|Response|Handler|Connection|Adapter|Status|Headers?|Key|Url|URL|Version|Config|Session|Auth|Token'

# Cada elemento es un patrón que debe casar con la entidad COMPLETA, distinguiendo mayúsculas
# (se aplica con grep -xE, sin -i): las variantes de caja admitidas están escritas.
SH01_CODE_PATTERNS=(
  # kwargs y literales
  'timeout=[0-9.]+' "(${_K})=[0-9]{1,5}" "${_L}=(True|False|None)" 'True|False|None'
  'kwargs' 'args|argv|stdin|stdout|stderr|self|cls|today|days|offset|substr|span|wdays'
  # palabras clave en minúscula seguidas de UN identificador de código (nunca un apellido)
  "(def|import|from|async|await|return) ${_L}${_DL}(\(\))?" 'class [A-Z][A-Za-z0-9_]*(\(\))?'
  '(throw|catch) [A-Z][A-Za-z0-9]*(Error|Exception)'
  # excepciones y avisos
  '(Base)?Exception|Error|Warning' '[A-Z][a-zA-Z]*(Error|Exception|Warning)'
  # módulos y espacios de nombres
  "urllib${_DL}" "websocket${_C}${_DL}" "(datetime|timedelta|zoneinfo|ZoneInfo)${_DL}(\(\)?)?"
  "(isoformat|fromisoformat|replace|Counter|OrderedDict|defaultdict|deque)(\(\)?)?"
  "(Microsoft|System|Azure|Google|Amazon)${_DS}" 'timezone\.utc\)?' 'utc\)'
  "(Start|Get|Stop)-Process" 'suppress_origin' 'iso8601'
  # siglas técnicas: la sigla sola o con un sufijo técnico de lista cerrada
  "(HTTPS?|REST|API|SDK)(${_AS})?" 'HTTPSConnection' 'Origin|CSRF|JSON|XML|Path'
  # red local: solo loopback o un puerto suelto
  '(localhost|127\.[0-9]+\.[0-9]+\.[0-9]+|0\.0\.0\.0)(:[0-9]{1,5})?' ':?(8080|8443|9222|9223)'
  # formatos de fecha
  '(YYYY|MM|DD|HH|SS)([-/: ](YYYY|MM|DD|HH|SS))*' '%?[YmdHMS]([-:/ T]%?[YmdHMS])+'
  # navegadores y CDP
  "(Dedup|webSocket|createTarget|devtools|DevTools|Chrome|Chromium|Playwright|Selenium|firefox|safari)${_C}${_DL}"
  "(page|ws)\.${_L}${_DL}(\(\))?" "\.stem${_DL}"
  'cdp_url|cdp_port|cdp_send|eval_in_page|find_page|ws_connect|discover_drive|list_recordings'
  'download_transcript|load_json|save_json|urlopen|tenant_url|drive_id|item_id|iso_str|out_dir|tenant_label'
  # git y herramientas
  'github(\.com|usercontent(\.com)?|_[A-Za-z0-9_]+)?|GitHub' 'git|repo|branch|commit|push|pull|merge|rebase|fetch|clone|linter'
  'TDD|BATS|pytest|jest|mocha|shellcheck|openpyxl|pandas|numpy|pathlib|typing'
  # vocabulario de programación
  'ast|regex|tokenize|serialize|deserialize|encode|decode|parse|render|template|format|string|number'
  'boolean|object|array|function|method|variable|constant|parameter|argument|keyword|lambda|generator'
  'iterator|decorator|annotation|interface|abstract|concrete|implementation|inheritance|polymorphism'
  'encapsulation|read|write|close|canonical|alias|aliases|resolved|applies|applied|real_to_canonical'
  # Azure DevOps y specs
  "(VSTS|Scheduling|TeamProject|WorkItemType|AssignedTo|IterationPath|AreaPath|ChangedDate|Effort|CompletedWork|RemainingWork)${_DS}"
  'SPEC-[A-Z0-9]+(-[A-Z0-9]+)*' "Hierarchy${_C}${_DS}" 'WorkItems?|LinkTypes?' 'SessionStart'
  'Parent|Tags|Priority|Title|State|Source|Detected|Tier|Errores|[Bb]loqueado'
  'pending|active|closed|deferred|discarded'
  # adjuntos y digest
  'SharePoint|Idempotency|attachments?( dispatcher)?|dispatch digests|manifests?|pre-downloaded'
  'download_dir|manifest_dir|digest_type|SUPPORTED_EXTS|sha256|file_hash|slugify|unsupported|dispatched'
  'skipped|dry-run' '\.(csv|xlsx|pdf|docx|pptx|doc|xls|ppt|md|sh|py|ps1|json|yaml|yml)'
  '([Bb]ase|[Aa]pi|[Tt]enant|[Dd]rive|[Ss]ite|[Ww]eb|[Dd]ownload|[Rr]edirect|[Cc]allback|[Rr]equest|[Ss]erver|[Ss]ervice|[Gg]raph|[Cc]dp|[Ww]s|[Pp]age|[Tt]arget|[Ee]ndpoint)Url'
  't = tag\.[A-Za-z0-9_]+' "separators=[][(),:'\" ]*"
  '(severity|id|priority|funcionalidad|excel_id|rule_code|incident_id) asc'
  'the extension|the file|a JWT|Found:?|Missing|Mirror|# Mirror'
)

# sh01_code_regex → la alternancia completa (para grep -xE, con mayúsculas).
sh01_code_regex() { local IFS='|'; printf '%s' "${SH01_CODE_PATTERNS[*]}"; }

# sh01_all_code_like <json del daemon> → 0 si se puede rebajar a aviso; 1 si no (fail-closed).
sh01_all_code_like() {
  local result="$1" texts non_code
  # Hay entidades, todas con tipo de nombre, texto no vacío y sin saltos de línea.
  printf '%s' "$result" | jq -e --arg nt "^(${SH01_NAME_TYPES})\$" '
    (.entities | type == "array" and length > 0) and
    all(.entities[]; ((.type // "") | test($nt)) and ((.text // "") | length > 0 and (test("\n") | not)))
  ' >/dev/null 2>&1 || return 1
  texts=$(printf '%s' "$result" | jq -r '.entities[].text' 2>/dev/null) || return 1
  [[ -n "$texts" ]] || return 1
  # clave=valor con clave de secreto: nunca es «solo código».
  if printf '%s\n' "$texts" | grep -qiE '(pwd|pass|secret|token|key|auth|cred)[A-Za-z0-9_]*[[:space:]]*='; then
    return 1
  fi
  # Con mayúsculas (sin -i): «Restrepo» no es REST ni «Terror» un Error.
  non_code=$(printf '%s\n' "$texts" | grep -vxE "$(sh01_code_regex)")
  [[ -z "$non_code" ]]
}
