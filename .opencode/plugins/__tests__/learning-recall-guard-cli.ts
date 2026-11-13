// learning-recall-guard-cli.ts — SE-515 S1: ejecuta el guard una vez con el texto de argv
// para comparar sus filas de emisión con las del hook bash (tests/test-se515-s1-recall-trazado.bats).
import { learningRecallGuard } from "../guards/learning-recall-guard.ts";

const text = process.argv[2] ?? "";
const output = {
  message: { id: "msg-cli", sessionID: "sess-cli" },
  parts: [{ id: "p1", sessionID: "sess-cli", messageID: "msg-cli", type: "text", text }],
};
await learningRecallGuard({ messageID: "msg-cli" }, output as any);
process.stdout.write(JSON.stringify({ injected: output.parts.length > 1 }) + "\n");
