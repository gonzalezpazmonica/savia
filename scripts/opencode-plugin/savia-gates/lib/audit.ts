// audit.ts — append-only audit log for plugin decisions

import { mkdir, appendFile } from "node:fs/promises"

// Resolved on every call, not at module load: the directory follows SAVIA_AUDIT_DIR as it is when the
// decision is logged (tests and embedders set it after the module is already imported).
function auditDir(): string {
  return process.env.SAVIA_AUDIT_DIR ?? `${process.env.HOME ?? ""}/.savia/audit`
}

const readyDirs = new Set<string>()

export interface AuditRecord {
  event: string
  [k: string]: unknown
}

export async function auditLog(rec: AuditRecord): Promise<void> {
  const dir = auditDir()
  if (!readyDirs.has(dir)) {
    await mkdir(dir, { recursive: true }).catch(() => {})
    readyDirs.add(dir)
  }
  const line =
    JSON.stringify({ ts: new Date().toISOString(), pid: process.pid, ...rec }) +
    "\n"
  await appendFile(`${dir}/savia-gates.jsonl`, line).catch(() => {})
}
