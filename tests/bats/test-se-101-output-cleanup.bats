#!/usr/bin/env bats
# test-se-101-output-cleanup.bats — SE-101: Output dir retention policy
# Verifies output-cleanup.sh behavior: exists, dry-run safety, telemetry protection.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/output-cleanup.sh"
OUTPUT_DIR="$REPO_ROOT/output"

@test "SE-101: output-cleanup.sh script exists and is executable" {
  [ -f "$SCRIPT" ] || { echo "Script missing: $SCRIPT" >&2; false; }
  [ -x "$SCRIPT" ] || { echo "Script not executable: $SCRIPT" >&2; false; }
  # Verify it accepts --dry-run without error
  run bash "$SCRIPT" --dry-run
  # Exit 0 means clean run (even if 0 stale files)
  [ "$status" -eq 0 ] || { echo "--dry-run failed with status $status: $output" >&2; false; }
}

@test "SE-101: --dry-run mode does not delete any files" {
  # Count files before dry-run
  before=$(find "$OUTPUT_DIR" -maxdepth 3 -type f 2>/dev/null | wc -l)
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ] || { echo "--dry-run exited $status" >&2; false; }
  after=$(find "$OUTPUT_DIR" -maxdepth 3 -type f 2>/dev/null | wc -l)
  # File count must not decrease (cleanup-log may be created, so after >= before-1 is ok,
  # but we allow +1 for the log file itself being created)
  [ "$after" -ge "$before" ] || { echo "Files deleted during dry-run! before=$before after=$after" >&2; false; }
  # Output must mention dry-run
  echo "$output" | grep -qi "dry-run" || { echo "Expected 'dry-run' in output: $output" >&2; false; }
}

@test "SE-101: protected telemetry files are excluded from dry-run candidate list" {
  run bash "$SCRIPT" --dry-run
  [ "$status" -eq 0 ] || { echo "--dry-run exited $status" >&2; false; }
  # These two files must never appear in the stale list
  echo "$output" | grep -qF "anti-adulation-telemetry.jsonl" \
    && { echo "anti-adulation-telemetry.jsonl appeared in cleanup list" >&2; false; }
  echo "$output" | grep -qF "quality-gate-history.jsonl" \
    && { echo "quality-gate-history.jsonl appeared in cleanup list" >&2; false; }
  :  # pass if neither protected file appears
}

# --- Comportamiento aislado: el script se copia a un arbol temporal ---

mk_tree() {
  T="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$T/scripts" "$T/output/pentesting" "$T/output/baselines" "$T/output/sub"
  cp "$SCRIPT" "$T/scripts/output-cleanup.sh"
  touch -d '200 days ago' "$T/output/old.md" "$T/output/sub/old2.md" \
    "$T/output/anti-adulation-telemetry.jsonl" "$T/output/quality-gate-history.jsonl" \
    "$T/output/pentesting/old-scan.md" "$T/output/baselines/b.json" \
    "$T/output/cleanup-log-19990101.txt"
  touch -d '10 days ago' "$T/output/recent.md"
  CLEAN="$T/scripts/output-cleanup.sh"
}

@test "SE-101 aislado: dry-run lista solo antiguos no protegidos y no borra nada" {
  mk_tree
  run bash "$CLEAN" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"(2 found)"* ]]
  [[ "$output" == *"output/old.md"* ]]
  [[ "$output" == *"output/sub/old2.md"* ]]
  [[ "$output" != *"recent.md"* ]]
  [[ "$output" != *"old-scan.md"* ]]
  [[ "$output" != *"b.json"* ]]
  [[ "$output" != *"anti-adulation"* ]]
  [[ "$output" != *"quality-gate-history"* ]]
  [[ "$output" == *"Dry-run complete. 2 file(s) would be deleted."* ]]
  [ -f "$T/output/old.md" ]
  [ -f "$T/output/sub/old2.md" ]
}

@test "SE-101 aislado: sin argumentos el modo por defecto es dry-run" {
  mk_tree
  run bash "$CLEAN"
  [ "$status" -eq 0 ]
  [ -f "$T/output/old.md" ]
}

@test "SE-101 aislado: la edad en dias se informa y SAVIA_OUTPUT_RETENTION_DAYS mueve la frontera" {
  mk_tree
  run env SAVIA_OUTPUT_RETENTION_DAYS=5 bash "$CLEAN" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"(3 found)"* ]]
  [[ "$output" == *"recent.md"* ]]
  [[ "$output" == *"[200d]"* ]]
  run env SAVIA_OUTPUT_RETENTION_DAYS=300 bash "$CLEAN" --dry-run
  [[ "$output" == *"No files older than 300 days"* ]]
}

@test "SE-101 aislado: --execute con 'y' borra los antiguos y respeta protegidos y recientes" {
  mk_tree
  run bash -c "echo y | bash '$CLEAN' --execute"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Deleted 2 file(s). 0 failed."* ]]
  [ ! -e "$T/output/old.md" ]
  [ ! -e "$T/output/sub/old2.md" ]
  [ -f "$T/output/recent.md" ]
  [ -f "$T/output/pentesting/old-scan.md" ]
  [ -f "$T/output/baselines/b.json" ]
  [ -f "$T/output/anti-adulation-telemetry.jsonl" ]
  [ -f "$T/output/quality-gate-history.jsonl" ]
  [ -f "$T/output/cleanup-log-19990101.txt" ]
}

@test "SE-101 aislado: --execute con 'n' aborta con 1 y no borra" {
  mk_tree
  run bash -c "echo n | bash '$CLEAN' --execute"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Aborted"* ]]
  [ -f "$T/output/old.md" ]
}

@test "SE-101 aislado: el log registra modo, candidatos y resultado" {
  mk_tree
  bash "$CLEAN" --dry-run >/dev/null
  log=$(ls "$T"/output/cleanup-log-2*.txt)
  grep -q "Mode: dry-run | Retention: 90d | Stale: 2" "$log"
  grep -q "stale: output/old.md" "$log"
  grep -q "Result: dry-run, no files deleted" "$log"
}

@test "SE-101 aislado: retencion invalida o argumento desconocido salen con 2" {
  mk_tree
  for v in 0 abc -3 1.5; do
    run env SAVIA_OUTPUT_RETENTION_DAYS="$v" bash "$CLEAN" --dry-run
    [ "$status" -eq 2 ]
    [[ "$output" == *"must be a positive integer"* ]]
  done
  run bash "$CLEAN" --nuke
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown argument"* ]]
}

@test "SE-101 aislado: sin directorio output sale con 2 y --help con 0" {
  mk_tree
  mv "$T/output" "$T/moved"
  run bash "$CLEAN" --dry-run
  [ "$status" -eq 2 ]
  [[ "$output" == *"output dir not found"* ]]
  run bash "$CLEAN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--execute"* ]]
}

@test "SE-101 aislado: ficheros mas hondos de 3 niveles no se consideran" {
  mk_tree
  mkdir -p "$T/output/a/b/c"
  touch -d '200 days ago' "$T/output/a/b/c/deep.md" "$T/output/a/b/ok.md"
  run bash "$CLEAN" --dry-run
  [[ "$output" == *"a/b/ok.md"* ]]
  [[ "$output" != *"deep.md"* ]]
}
