#!/usr/bin/env bash
# engagement-separation-proof.sh — SE-271 S3: Generates verifiable separation proof
# Produces auditable evidence that client walls are functioning.
# Uses verifiable sampling (not declarative statement) — adversarial self-test.
# Planted contamination MUST be detectable.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGAGEMENTS_DIR="$ROOT/engagements"

usage() {
  cat <<EOF
Usage: bash scripts/engagement-separation-proof.sh [options] COMMAND

Commands:
  generate    Generate separation proof for client engagement
  verify      Verify an existing separation proof
  test        Run adversarial self-test: plant contamination, verify detection
  all         Generate proof for all active engagements

Options:
  --client CLIENT       Client slug (required for generate/verify)
  --engagement NAME     Engagement name (required for generate/verify)
  --output PATH         Output file for proof (default: stdout)
  --sample-count N      Number of artifacts to sample (default: 20)
  --plant-contamination Plant test contamination before verification
  --json                Output JSON only
  --help, -h            This help
EOF
}

CMD=""; CLIENT=""; ENGAGEMENT=""; OUTPUT=""; SAMPLE_COUNT=20
PLANT_CONTAMINATION=false; JSON_OUT=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    generate|verify|test|all) CMD="$1"; shift ;;
    --client)              CLIENT="$2";              shift 2 ;;
    --engagement)          ENGAGEMENT="$2";          shift 2 ;;
    --output)              OUTPUT="$2";               shift 2 ;;
    --sample-count)        SAMPLE_COUNT="$2";         shift 2 ;;
    --plant-contamination) PLANT_CONTAMINATION=true;  shift ;;
    --json)                JSON_OUT=true;             shift ;;
    --help|-h)             usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$CMD" ]]; then usage >&2; exit 1; fi

DATE_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PROOF_ID="SEP-$(date -u +"%Y%m%d%H%M%S")-$$"

# ── Resolve engagement ───────────────────────────────────────────────────
resolve_engagements() {
  if [[ -z "$CLIENT" ]]; then
    if [[ -d "$ENGAGEMENTS_DIR" ]]; then
      for client_dir in "$ENGAGEMENTS_DIR"/*/; do
        [[ -d "$client_dir" ]] || continue
        local cslug; cslug=$(basename "$client_dir")
        for yf in "$client_dir"/*.yaml; do
          [[ -f "$yf" ]] || continue
          local ename status
          ename=$(basename "$yf" .yaml)
          status=$(grep -E "^\s+active:" "$yf" 2>/dev/null | head -1 | awk '{print $2}')
          [[ "$status" == "true" ]] && echo "$cslug|$ename|$yf"
        done
      done
    fi
  elif [[ -n "$ENGAGEMENT" ]]; then
    local yf="$ENGAGEMENTS_DIR/$CLIENT/${ENGAGEMENT}.yaml"
    [[ -f "$yf" ]] && echo "$CLIENT|$ENGAGEMENT|$yf"
  else
    if [[ -d "$ENGAGEMENTS_DIR/$CLIENT" ]]; then
      for yf in "$ENGAGEMENTS_DIR/$CLIENT"/*.yaml; do
        [[ -f "$yf" ]] || continue
        local ename; ename=$(basename "$yf" .yaml)
        echo "$CLIENT|$ename|$yf"
      done
    fi
  fi
}

# ── Collect samples (engagement dirs prioritized) ─────────────────────────
collect_samples() {
  local cslug="$1" count="$2"
  local samples=()
  local eng_dir="$ENGAGEMENTS_DIR/$cslug"

  # 1. Collect all engagement-specific files first
  local eng_find_dirs=(
    "$eng_dir/artifacts"
    "$eng_dir/memory"
    "$eng_dir/ledger"
    "$eng_dir/wall"
  )
  local eng_files=()
  for dir in "${eng_find_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' f; do
      [[ -f "$f" ]] || continue
      local sz; sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
      [[ "$sz" -gt 0 ]] || continue
      eng_files+=("$f")
    done < <(find "$dir" -type f \( -name "*.md" -o -name "*.json" -o -name "*.jsonl" -o -name "*.yaml" \) -print0 2>/dev/null)
  done

  # 2. Collect global files for broader sampling
  local global_dirs=(
    "$ROOT/output"
    "$ROOT/.claude/profiles"
    "$ROOT/coordinacion/exchange"
  )
  local global_files=()
  for dir in "${global_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' f; do
      [[ -f "$f" ]] || continue
      local sz; sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
      [[ "$sz" -gt 0 ]] || continue
      global_files+=("$f")
    done < <(find "$dir" -maxdepth 3 -type f \( -name "*.md" -o -name "*.json" -o -name "*.jsonl" -o -name "*.yaml" \) -print0 2>/dev/null)
  done

  # 3. Allocate half the samples to engagement-specific files
  local eng_slots=$(( count / 2 ))
  [[ $eng_slots -lt 1 ]] && eng_slots=1

  local i=0
  for f in "${eng_files[@]}"; do
    [[ $i -ge $eng_slots ]] && break
    samples+=("$f")
    i=$((i + 1))
  done

  # 4. Fill remaining samples from global files (hash-based)
  local remaining=$(( count - ${#samples[@]} ))
  for f in "${global_files[@]}"; do
    [[ ${#samples[@]} -ge "$count" ]] && break
    local hv; hv=$(echo -n "$f" | sha256sum 2>/dev/null | awk '{print $1}' || echo "00000000")
    local hi; hi=$((16#${hv:0:8}))
    if [[ $((hi % 5)) -eq 0 ]]; then samples+=("$f"); fi
  done

  # 5. Fallback: fill remaining from any file
  if [[ ${#samples[@]} -lt "$count" ]]; then
    for f in "${eng_files[@]}" "${global_files[@]}"; do
      [[ " ${samples[*]} " =~ " ${f} " ]] && continue
      samples+=("$f")
      [[ ${#samples[@]} -ge "$count" ]] && break
    done
  fi

  for s in "${samples[@]}"; do echo "$s"; done
}

# ── Check sample for client tag ───────────────────────────────────────────
check_sample() {
  local file="$1" expected_client="$2"
  local result="clean" tag=""

  [[ ! -f "$file" ]] && { echo "missing|$file||"; return; }

  # Etiqueta completa y literal: «client:acme» no puede dar por buena
  # «client:acme-corp» (prefijo) ni el slug entrar en una regex («a.b» ≠ «axb»).
  local all_tags
  all_tags=$(grep -oE 'client:[a-z0-9][a-z0-9-]*' "$file" 2>/dev/null || true)
  if grep -qxF -- "client:${expected_client}" <<< "$all_tags"; then
    result="tagged-correct"
    tag="$expected_client"
  fi

  local other_tags
  other_tags=$(grep -vxF -- "client:${expected_client}" <<< "$all_tags" | grep -v '^$' | sort -u | head -5 || true)
  if [[ -n "$other_tags" ]]; then
    result=$([[ "$result" == "tagged-correct" ]] && echo "cross-contaminated" || echo "contaminated")
    tag=$(echo "$other_tags" | tr '\n' ',' | sed 's/,$//')
  fi

  if [[ "$result" == "clean" ]]; then
    if ! grep -qE 'client:[a-z0-9][a-z0-9-]*' "$file" 2>/dev/null; then
      result="untagged"
    else
      result="other-client"
      tag=$(grep -oE 'client:[a-z0-9][a-z0-9-]*' "$file" 2>/dev/null | head -1 | cut -d: -f2 || echo "unknown")
    fi
  fi

  local hash; hash=$(sha256sum "$file" 2>/dev/null | awk '{print $1}' || echo "hash-error")
  echo "${result}|${file}|${hash}|${tag}"
}

# ── Plant contamination ───────────────────────────────────────────────────
plant_contamination() {
  local cslug="$1"
  local eng_dir="$ENGAGEMENTS_DIR/$cslug"
  local fake_client="adversary-client-$$"
  local contam_file="$eng_dir/artifacts/planted-contamination-$$.md"
  mkdir -p "$eng_dir/artifacts"
  cat > "$contam_file" << EOF
# Planted contamination for adversarial test
This file pretends to belong to client:${fake_client} but is in client:${cslug} space.
Generated: $DATE_NOW
<!-- SE-271-WALL client:${fake_client} engagement:test min-level:3 -->
EOF
  echo "$contam_file"
}

cleanup_contamination() {
  local file="$1"
  [[ -f "$file" ]] && rm -f "$file"
}

# ── Generate proof ────────────────────────────────────────────────────────
cmd_generate() {
  local proof_entries="["
  local first=true
  local total_samples=0 clean_samples=0 contaminated=0 untagged=0

  while IFS= read -r eng; do
    [[ -n "$eng" ]] || continue
    IFS='|' read -r cslug ename yf <<< "$eng"

    local sample_arr=()
    while IFS= read -r s; do [[ -n "$s" ]] && sample_arr+=("$s"); done < <(collect_samples "$cslug" "$SAMPLE_COUNT")

    local eng_entries="[" eng_first=true

    for s in "${sample_arr[@]}"; do
      total_samples=$((total_samples + 1))
      local check_result; check_result=$(check_sample "$s" "$cslug")
      IFS='|' read -r status fpath fhash ftag <<< "$check_result"

      case "$status" in
        tagged-correct) clean_samples=$((clean_samples + 1)) ;;
        cross-contaminated|contaminated) contaminated=$((contaminated + 1)) ;;
        untagged) untagged=$((untagged + 1)) ;;
      esac

      if ! $eng_first; then eng_entries+=","; fi
      eng_first=false
      local epath; epath=$(echo "$fpath" | tr '"' "'" | head -c 300)
      local etag; etag=$(echo "$ftag" | tr '"' "'" | head -c 100)
      eng_entries+="{\"status\":\"$status\",\"path\":\"$epath\",\"sha256\":\"$fhash\",\"tag\":\"$etag\"}"
    done
    eng_entries+="]"

    if ! $first; then proof_entries+=","; fi
    first=false
    local wmode; wmode=$(grep -E "^\s+mode:" "$yf" 2>/dev/null | head -1 | awk '{print $2}' | tr -d '"' || echo "strict")
    proof_entries+="{\"client\":\"$cslug\",\"engagement\":\"$ename\",\"wall\":\"$wmode\",\"samples\":$eng_entries}"
  done < <(resolve_engagements)
  proof_entries+="]"

  # Build JSON via temp file to avoid shell escaping issues
  local tmp_json="/tmp/se271-proof-$$.json"
  python3 - "$PROOF_ID" "$DATE_NOW" "$total_samples" "$clean_samples" "$contaminated" "$untagged" "$proof_entries" "$PLANT_CONTAMINATION" << 'PYEOF' > "$tmp_json" 2>/dev/null
import json, sys
pid = sys.argv[1]
ts = sys.argv[2]
total = int(sys.argv[3])
clean = int(sys.argv[4])
cont = int(sys.argv[5])
unt = int(sys.argv[6])
entries_raw = sys.argv[7]
adv = sys.argv[8] == 'true'

entries = json.loads(entries_raw)
proof = {
    "proof_id": pid,
    "generated_at": ts,
    "adversarial_test": adv,
    "summary": {
        "total_samples": total,
        "clean": clean,
        "contaminated": cont,
        "untagged": unt,
        "separation_intact": cont == 0
    },
    "engagements": entries
}
print(json.dumps(proof, indent=2))
PYEOF

  if [[ -n "$OUTPUT" ]]; then
    cp "$tmp_json" "$OUTPUT" 2>/dev/null
  else
    cat "$tmp_json" 2>/dev/null
  fi
  rm -f "$tmp_json"

  return $([[ $contaminated -eq 0 ]] && echo 0 || echo 1)
}

# ── Verify proof ──────────────────────────────────────────────────────────
cmd_verify() {
  if [[ -z "$CLIENT" ]]; then
    echo '{"error":"--client required for verify"}' >&2; exit 1
  fi
  local fresh; fresh=$(bash "$0" generate --client "$CLIENT" ${ENGAGEMENT:+--engagement "$ENGAGEMENT"} --json 2>/dev/null) || true
  local contaminated_now
  contaminated_now=$(echo "$fresh" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['summary']['contaminated'])" 2>/dev/null || echo "-1")
  if $JSON_OUT; then
    local verified=false; [[ "$contaminated_now" -eq 0 ]] && verified=true
    echo '{"verified":'"$verified"',"client":"'"$CLIENT"'","engagement":"'"${ENGAGEMENT:-}"'","current_contamination":'"$contaminated_now"',"verified_at":"'"$DATE_NOW"'"}'
  else
    echo "=== Verification for $CLIENT / ${ENGAGEMENT:-all} ==="
    echo "  Verified at: $DATE_NOW"
    echo "  Current contamination: $contaminated_now"
    [[ "$contaminated_now" -eq 0 ]] && echo "  SEPARATION INTACT" || echo "  VIOLATION DETECTED"
  fi
  return $([[ "$contaminated_now" -eq 0 ]] && echo 0 || echo 1)
}

# ── Adversarial self-test ─────────────────────────────────────────────────
cmd_test() {
  echo "=== Adversarial Self-Test: Plant contamination, then detect ==="

  if [[ -z "$CLIENT" ]]; then
    echo "ERROR: --client required for adversarial test" >&2; exit 1
  fi

  echo "[1/4] Planting contamination in client:$CLIENT space..."
  local contam_file; contam_file=$(plant_contamination "$CLIENT")
  echo "  Planted: $contam_file"

  echo "[2/4] Running wall-check..."
  local wall_output wall_violations=0
  wall_output=$(bash "$SCRIPT_DIR/engagement-wall-check.sh" --client "$CLIENT" --strict --json 2>/dev/null) || true
  if [[ "$wall_output" == '['* ]]; then
    wall_violations=$(echo "$wall_output" | python3 -c "import json,sys; a=json.loads(sys.stdin.read()); print(len(a))" 2>/dev/null || echo "0")
  else
    wall_violations=$(echo "$wall_output" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('violation_count',0))" 2>/dev/null || echo "0")
  fi

  echo "[3/4] Running separation proof..."
  local proof_output proof_contamination=0
  proof_output=$(bash "$0" generate --client "$CLIENT" --json --sample-count 20 2>/dev/null) || true
  proof_contamination=$(echo "$proof_output" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['summary']['contaminated'])" 2>/dev/null || echo "0")

  echo "[4/4] Cleaning up planted contamination..."
  cleanup_contamination "$contam_file"

  local wall_pass=$([[ "$wall_violations" -gt 0 ]] && echo "DETECTED" || echo "MISSED")
  local proof_pass=$([[ "$proof_contamination" -gt 0 ]] && echo "DETECTED" || echo "MISSED")
  local overall_pass=false
  [[ "$wall_violations" -gt 0 ]] || [[ "$proof_contamination" -gt 0 ]] && overall_pass=true

  if $JSON_OUT; then
    python3 -c "
import json
print(json.dumps({
    'adversarial_test': True,
    'client': '$CLIENT',
    'planted_contamination': 'adversary-client-$$',
    'wall_check': {'violations': $wall_violations, 'result': '$wall_pass'},
    'separation_proof': {'contamination': $proof_contamination, 'result': '$proof_pass'},
    'overall': '$([[ $overall_pass == true ]] && echo 'PASS' || echo 'FAIL')',
    'tested_at': '$DATE_NOW'
}, indent=2))
" 2>/dev/null || echo '{"adversarial_test":true,"overall":"UNKNOWN"}'
  else
    echo ""
    echo "=== Results ==="
    echo "  Wall check violations:     $wall_violations ($wall_pass)"
    echo "  Separation proof contamin: $proof_contamination ($proof_pass)"
    echo ""
    if $overall_pass; then
      echo "  TEST PASSED: Planted contamination detected by wall"
      echo "  Separation proof IS verifiable (not just declarative)"
    else
      echo "  TEST FAILED: Planted contamination was NOT detected"
      echo "  Walls are declarative only — not actually enforced"
    fi
  fi
  $overall_pass && exit 0 || exit 1
}

# ── Generate for all engagements ──────────────────────────────────────────
cmd_all() {
  local all_proof="[" first=true total_clean=0 total_contaminated=0 eng_count=0 parse_errors=0
  while IFS= read -r eng; do
    [[ -n "$eng" ]] || continue
    IFS='|' read -r cslug ename yf <<< "$eng"
    eng_count=$((eng_count + 1))
    local proof; proof=$(bash "$0" generate --client "$cslug" --engagement "$ename" --json --sample-count 5 2>/dev/null) || true
    if ! $first; then all_proof+=","; fi; first=false
    # Nombres por argv, nunca interpolados en el código Python (inyección con «'»).
    local eng_json; eng_json=$(echo "$proof" | python3 -c "import json,sys;d=json.load(sys.stdin);s=d['summary'];print(json.dumps({'client':sys.argv[1],'engagement':sys.argv[2],'clean':s['clean'],'contaminated':s['contaminated']}))" "$cslug" "$ename" 2>/dev/null || echo '{"client":"'"${cslug//[\\\"]/_}"'","engagement":"'"${ename//[\\\"]/_}"'","error":"parse-failed"}')
    all_proof+="$eng_json"
    # Fail-closed: una prueba que no se puede leer NO cuenta como «sin contaminación».
    local cont; cont=$(echo "$proof" | python3 -c "import json,sys;print(json.load(sys.stdin)['summary']['contaminated'])" 2>/dev/null) || { cont=0; parse_errors=$((parse_errors + 1)); }
    local cl; cl=$(echo "$proof" | python3 -c "import json,sys;print(json.load(sys.stdin)['summary']['clean'])" 2>/dev/null) || cl=0
    total_contaminated=$((total_contaminated + cont)); total_clean=$((total_clean + cl))
  done < <(resolve_engagements)
  all_proof+="]"
  # Fail-closed: sin engagements evaluados no hay prueba de separación.
  local intact=false
  [[ $eng_count -gt 0 && $total_contaminated -eq 0 && $parse_errors -eq 0 ]] && intact=true
  if $JSON_OUT; then
    echo "{\"proof_id\":\"$PROOF_ID\",\"generated_at\":\"$DATE_NOW\",\"total_engagements\":$eng_count,\"total_clean\":$total_clean,\"total_contaminated\":$total_contaminated,\"parse_errors\":$parse_errors,\"separation_intact\":$intact,\"engagements\":$all_proof}"
  else
    echo "=== Separation Proof: All Engagements ==="
    echo "  Proof ID:     $PROOF_ID"
    echo "  Engagements:  $eng_count"
    echo "  Total clean:  $total_clean"
    echo "  Total viol:   $total_contaminated"
    echo "  Parse errors: $parse_errors"
    if $intact; then echo "  SEPARATION INTACT"
    elif [[ $eng_count -eq 0 ]]; then echo "  NO ENGAGEMENTS EVALUATED"
    else echo "  VIOLATIONS DETECTED"; fi
  fi
  $intact && return 0 || return 1
}

case "$CMD" in
  generate) cmd_generate ;;
  verify)   cmd_verify ;;
  test)     cmd_test ;;
  all)      cmd_all ;;
  *)        echo "ERROR: unknown command '$CMD'" >&2; exit 1 ;;
esac
