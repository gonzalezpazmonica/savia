#!/usr/bin/env bash
# sh01-code-allowlist.sh — SPEC-SH01 / SE-453 S6: ¿todas las entidades del shield son código?
# Lo usa data-sovereignty-gate.sh para rebajar un BLOCK a aviso en ficheros de código.
#
# Antes (hasta SE-453 S6) la lista era un `grep -viE` sin ancla final: una entidad que solo EMPEZABA
# (Microsoft…, from …, HTTP…), TERMINABA (…:8080, …=123) o CONTENÍA (timeout=) una palabra de código
# se rebajaba aunque el resto fuera un dato real (docs/evidence/SE-453-S4-evidence-grading.md).
# Ahora cada patrón casa con la entidad ENTERA (grep -x) y, además, fail-closed:
#   - toda entidad debe tener un tipo de nombre (NER); credencial/IP/URL/email/sin tipo → nunca se rebaja;
#   - un clave=valor cuya clave parece secreto (pwd, pass, secret, token, key, auth, cred) → nunca;
#   - una entidad con salto de línea o vacía → nunca.

# Tipos NER de nombre (mismos que el relajo N3/N4 del hook, más DATE_TIME de Presidio).
SH01_NAME_TYPES='PERSON|PERSON_ES|ORG|ORGANIZATION|LOCATION|GPE|DATE|TIME|DATE_TIME|NRP|EVENT|PRODUCT|WORK_OF_ART|MISC|LAW|LANGUAGE|ORDINAL|CARDINAL|QUANTITY|PERCENT|MONEY'

# Piezas de forma: identificador, sufijo de identificador, segmentos con punto.
_I='[A-Za-z_][A-Za-z0-9_]*'
_S='[A-Za-z0-9_]*'
_D='(\.[A-Za-z0-9_]+)*'

# Cada elemento es un patrón que debe casar con la entidad COMPLETA (se aplica con grep -ixE).
SH01_CODE_PATTERNS=(
  # kwargs y literales
  'timeout=[0-9.]+' "${_I}=[0-9]{1,5}" "${_I}=(True|False|None)" 'default=[0-9]+' 'True|False|None'
  'kwargs' 'args|argv|stdin|stdout|stderr|self|cls|today|days|offset|substr|span|wdays'
  # palabras clave seguidas de UN identificador (nunca una frase)
  "(class|def|import|from|async|await|return|throw|catch) ${_I}${_D}(\(\))?"
  # excepciones y avisos
  '(Base)?Exception' '[A-Z][a-zA-Z]*(Error|Exception|Warning)'
  # módulos y espacios de nombres
  "urllib${_D}" "websocket${_S}${_D}" "(datetime|timedelta|zoneinfo|ZoneInfo)${_D}(\(\)?)?"
  "(isoformat|fromisoformat|replace|Counter|OrderedDict|defaultdict|deque)(\(\)?)?"
  "Microsoft${_D}" "(System|Azure|Google|Amazon)${_D}" 'timezone\.utc\)?' 'utc\)'
  "(Start|Get|Stop)-Process" 'suppress_origin' 'iso8601'
  # siglas técnicas: la sigla más [A-Za-z0-9]*, sin guiones, espacios ni barras
  '(HTTPS?|REST|API|SDK)[A-Za-z0-9]*' 'Origin|CSRF|JSON|XML|Path'
  # red local: solo loopback o un puerto suelto
  '(localhost|127\.[0-9]+\.[0-9]+\.[0-9]+|0\.0\.0\.0)(:[0-9]{1,5})?' ':?(8080|8443|9222|9223)'
  # formatos de fecha
  '(YYYY|MM|DD|HH|SS)([-/: ](YYYY|MM|DD|HH|SS))*' '%?[YmdHMS]([-:/ T]%?[YmdHMS])+'
  # navegadores y CDP
  "(Dedup|webSocket|createTarget|devtools|DevTools|Chrome|Chromium|Playwright|Selenium|firefox|safari)${_S}${_D}"
  "(page|ws)\.${_I}${_D}(\(\))?" "\.stem${_D}"
  'cdp_url|cdp_port|cdp_send|eval_in_page|find_page|ws_connect|discover_drive|list_recordings'
  'download_transcript|load_json|save_json|urlopen|tenant_url|drive_id|item_id|iso_str|out_dir|tenant_label'
  # git y herramientas
  'github([A-Za-z0-9]*|\.com)' 'git|repo|branch|commit|push|pull|merge|rebase|fetch|clone|linter'
  'TDD|BATS|pytest|jest|mocha|shellcheck|openpyxl|pandas|numpy|pathlib|typing'
  # vocabulario de programación
  'ast|regex|tokenize|serialize|deserialize|encode|decode|parse|render|template|format|string|number'
  'boolean|object|array|function|method|variable|constant|parameter|argument|keyword|lambda|generator'
  'iterator|decorator|annotation|interface|abstract|concrete|implementation|inheritance|polymorphism'
  'encapsulation|read|write|close|canonical|alias|aliases|resolved|applies|applied|real_to_canonical'
  # Azure DevOps y specs
  "(VSTS|Scheduling|TeamProject|WorkItemType|AssignedTo|IterationPath|AreaPath|ChangedDate|Effort|CompletedWork|RemainingWork)${_D}"
  'SPEC-[A-Z0-9]+(-[A-Z0-9]+)*' "Hierarchy${_S}${_D}" 'WorkItems?|LinkTypes?' 'SessionStart'
  'Parent|Tags|Priority|Title|State|Source|Detected|Tier|Errores|[Bb]loqueado'
  'pending|active|closed|deferred|discarded'
  # adjuntos y digest
  'SharePoint|Idempotency|attachments?( dispatcher)?|dispatch digests|manifests?|pre-downloaded'
  'download_dir|manifest_dir|digest_type|SUPPORTED_EXTS|sha256|file_hash|slugify|unsupported|dispatched'
  'skipped|dry-run' '\.(csv|xlsx|pdf|docx|pptx|doc|xls|ppt|md|sh|py|ps1|json|yaml|yml)'
  '[A-Z][a-zA-Z]+Url' 't = tag\.[A-Za-z0-9_]+' "separators=[][(),:'\" ]*"
  '(severity|id|priority|funcionalidad|excel_id|rule_code|incident_id) asc'
  'the extension|the file|a JWT|Found:?|Missing|Mirror|# Mirror'
)

# sh01_code_regex → la alternancia completa (para grep -ixE).
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
  non_code=$(printf '%s\n' "$texts" | grep -vixE "$(sh01_code_regex)")
  [[ -z "$non_code" ]]
}
