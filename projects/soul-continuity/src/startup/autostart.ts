/**
 * Arranque sin administrador (SE-490, AC-1):
 *   - Linux: unidad `systemd --user` en ~/.config/systemd/user;
 *   - macOS: `LaunchAgent` en ~/Library/LaunchAgents;
 *   - Windows: tarea de inicio de sesión del usuario con privilegio mínimo (schtasks /XML).
 *
 * El modo por defecto de Soul es bajo demanda: esto solo se usa si el operador lo pide
 * (`soul autostart install`). Arrancar el servicio no concede ningún permiso. Las órdenes
 * se ejecutan con un `Run` inyectado para poder probarlas sin tocar la máquina.
 */

import { existsSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type { Run } from "../credentials/store.ts";

export interface AutostartOptions {
  platform: NodeJS.Platform;
  home: string;
  env: Record<string, string | undefined>;
  /** Ruta del runtime oficial de Node.js. */
  node: string;
  /** Punto de entrada de la CLI (`src/cli/main.ts`). */
  entry: string;
}

export interface Command { cmd: string; args: string[] }
export interface AutostartPlan { files: { path: string; content: string }[]; enable: Command[]; disable: Command[] }

const LABEL = "org.savia.soul-continuity";
const TASK = "Savia\\SoulContinuity";
const NODE_FLAGS = ["--experimental-strip-types", "--no-warnings"];

const xml = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
const sdQuote = (s: string) => `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
const winQuote = (s: string) => `"${s.replace(/"/g, '\\"')}"`;

export function autostartPlan(o: AutostartOptions): AutostartPlan {
  const argv = [...NODE_FLAGS, o.entry, "serve"];
  if (o.platform === "linux") {
    const path = join(o.env.XDG_CONFIG_HOME || join(o.home, ".config"), "systemd", "user", "soul-continuity.service");
    const content = [
      "[Unit]",
      "Description=Savia Soul Continuidad (por usuario, solo lectura)",
      "",
      "[Service]",
      "Type=simple",
      `ExecStart=${[o.node, ...argv].map(sdQuote).join(" ")}`,
      "Restart=on-failure",
      "RestartSec=30",
      "NoNewPrivileges=yes",
      "PrivateTmp=yes",
      "",
      "[Install]",
      "WantedBy=default.target",
      "",
    ].join("\n");
    return {
      files: [{ path, content }],
      enable: [{ cmd: "systemctl", args: ["--user", "daemon-reload"] }, { cmd: "systemctl", args: ["--user", "enable", "--now", "soul-continuity.service"] }],
      disable: [{ cmd: "systemctl", args: ["--user", "disable", "--now", "soul-continuity.service"] }, { cmd: "systemctl", args: ["--user", "daemon-reload"] }],
    };
  }
  if (o.platform === "darwin") {
    const path = join(o.home, "Library", "LaunchAgents", `${LABEL}.plist`);
    const content = [
      '<?xml version="1.0" encoding="UTF-8"?>',
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">',
      '<plist version="1.0">',
      "<dict>",
      `  <key>Label</key><string>${LABEL}</string>`,
      "  <key>ProgramArguments</key>",
      "  <array>",
      ...[o.node, ...argv].map((a) => `    <string>${xml(a)}</string>`),
      "  </array>",
      "  <key>RunAtLoad</key><true/>",
      "  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>",
      "  <key>ProcessType</key><string>Background</string>",
      "</dict>",
      "</plist>",
      "",
    ].join("\n");
    return {
      files: [{ path, content }],
      enable: [{ cmd: "launchctl", args: ["load", "-w", path] }],
      disable: [{ cmd: "launchctl", args: ["unload", "-w", path] }],
    };
  }
  if (o.platform === "win32") {
    const path = join(o.env.LOCALAPPDATA || join(o.home, "AppData", "Local"), "Savia", "soul-continuity", "autostart-task.xml");
    const content = [
      '<?xml version="1.0" encoding="UTF-16"?>',
      '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">',
      "  <RegistrationInfo><Description>Savia Soul Continuidad (por usuario, solo lectura)</Description></RegistrationInfo>",
      "  <Triggers><LogonTrigger><Enabled>true</Enabled></LogonTrigger></Triggers>",
      "  <Principals><Principal id=\"Author\"><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>",
      "  <Settings><MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy><DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>",
      "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries><ExecutionTimeLimit>PT0S</ExecutionTimeLimit><Hidden>true</Hidden></Settings>",
      "  <Actions Context=\"Author\"><Exec>",
      `    <Command>${xml(o.node)}</Command>`,
      `    <Arguments>${xml(argv.map(winQuote).join(" "))}</Arguments>`,
      "  </Exec></Actions>",
      "</Task>",
      "",
    ].join("\n");
    return {
      files: [{ path, content }],
      enable: [{ cmd: "schtasks", args: ["/Create", "/TN", TASK, "/XML", path, "/F"] }, { cmd: "schtasks", args: ["/Run", "/TN", TASK] }],
      disable: [{ cmd: "schtasks", args: ["/End", "/TN", TASK] }, { cmd: "schtasks", args: ["/Delete", "/TN", TASK, "/F"] }],
    };
  }
  throw new Error(`arranque automático no soportado en ${o.platform}`);
}

export interface AutostartResult { ok: boolean; message: string; planned: string[] }

const show = (c: Command) => [c.cmd, ...c.args].join(" ");

export async function installAutostart(o: AutostartOptions, run: Run, opts: { dryRun?: boolean } = {}): Promise<AutostartResult> {
  const plan = autostartPlan(o);
  const planned = [...plan.files.map((f) => `escribir ${f.path}`), ...plan.enable.map(show)];
  if (opts.dryRun) return { ok: true, message: "simulación: no se ha escrito ni ejecutado nada", planned };
  for (const f of plan.files) {
    mkdirSync(dirname(f.path), { recursive: true });
    // Windows exige UTF-16 con BOM para el XML de schtasks.
    if (o.platform === "win32") writeFileSync(f.path, "﻿" + f.content, "utf16le");
    else writeFileSync(f.path, f.content, { mode: 0o644 });
  }
  for (const c of plan.enable) {
    const r = await run(c.cmd, c.args);
    if (r.code !== 0) return { ok: false, message: `falló «${show(c)}»: ${r.stderr.trim() || `código ${r.code}`}`, planned };
  }
  return { ok: true, message: "arranque automático activado para este usuario", planned };
}

export async function uninstallAutostart(o: AutostartOptions, run: Run, opts: { dryRun?: boolean } = {}): Promise<AutostartResult> {
  const plan = autostartPlan(o);
  const planned = [...plan.disable.map(show), ...plan.files.map((f) => `borrar ${f.path}`)];
  if (opts.dryRun) return { ok: true, message: "simulación: no se ha borrado ni ejecutado nada", planned };
  const errors: string[] = [];
  // Desactivar puede fallar si nunca se activó: se sigue y se borran los ficheros igualmente.
  for (const c of plan.disable) {
    const r = await run(c.cmd, c.args);
    if (r.code !== 0) errors.push(`${show(c)}: ${r.stderr.trim() || `código ${r.code}`}`);
  }
  for (const f of plan.files) if (existsSync(f.path)) rmSync(f.path, { force: true });
  const left = plan.files.filter((f) => existsSync(f.path)).map((f) => f.path);
  if (left.length) return { ok: false, message: `no se pudieron borrar: ${left.join(", ")}`, planned };
  return { ok: true, message: errors.length ? `ficheros borrados; avisos al desactivar: ${errors.join("; ")}` : "arranque automático retirado", planned };
}
