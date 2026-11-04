// Tipos de lanzador.mjs (JavaScript puro para que corra en cualquier Node).
export interface Probe { ok: boolean; version: string | null; noTs?: boolean }
export interface Failure extends Probe { node: string }
export declare const NODE_FLAGS: string[];
export declare function nodeCandidates(o: { env: Record<string, string | undefined>; home: string; platform: NodeJS.Platform; execPath: string }): string[];
export declare function probeNode(node: string): Probe;
export declare function chooseNode(candidates: string[], probe?: (node: string) => Probe): { node: string | null; version?: string | null; failures: Failure[] };
export declare function noNodeMessage(failures: Failure[], pkgDir: string, platform: NodeJS.Platform): string;
export declare function makeProbe(self: { execPath: string; typescript?: unknown; version: string }, probe?: (node: string) => Probe): (node: string) => Probe;
export declare function launch(o: {
  execPath: string; typescript?: unknown; version: string; env: Record<string, string | undefined>; home: string; platform: NodeJS.Platform;
  pkg: string; entry: string; argv: string[]; stderr: (s: string) => void;
  probe?: (node: string) => Probe; spawn?: (cmd: string, args: string[], opts: object) => { status: number | null };
}): number;
