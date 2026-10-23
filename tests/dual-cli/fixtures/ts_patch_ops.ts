// Prints the OpenCode port of apply_patch_operations for each patch, to compare with gates.py.
import { applyPatchOperations } from "../../../scripts/opencode-plugin/savia-gates/lib/hook-vocabulary"

const cases: { patch: unknown; cwd: string }[] = JSON.parse(await Bun.stdin.text())
console.log(JSON.stringify(cases.map((c) => {
  try {
    return applyPatchOperations(c.patch, c.cwd)
  } catch (e) {
    return String((e as Error).message)
  }
})))
