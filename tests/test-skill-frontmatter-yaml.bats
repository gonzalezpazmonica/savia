#!/usr/bin/env bats

@test "all SKILL.md frontmatter is valid YAML" {
  run python3 - "$BATS_TEST_DIRNAME/.." <<'PY'
from pathlib import Path
import re
import sys

import yaml

root = Path(sys.argv[1]).resolve()
failures = []
for path in sorted((root / ".claude" / "skills").glob("**/SKILL.md")):
    text = path.read_text(encoding="utf-8")
    match = re.match(r"^---\n(.*?)\n---(?:\n|$)", text, re.DOTALL)
    if match is None:
        failures.append(f"{path.relative_to(root)}: missing frontmatter")
        continue
    try:
        value = yaml.safe_load(match.group(1))
    except yaml.YAMLError as error:
        failures.append(f"{path.relative_to(root)}: {error}")
        continue
    if not isinstance(value, dict) or not value.get("name") or not value.get("description"):
        failures.append(f"{path.relative_to(root)}: missing name or description")

if failures:
    print("\n".join(failures))
    raise SystemExit(1)
PY

  [ "$status" -eq 0 ]
}
