// WebSocket mínimo (RFC 6455, solo texto) para el sitio sintético de correo.
// Sin dependencias: basta para que el banco observe envíos del navegador.

import { createHash } from "node:crypto";
import type { IncomingMessage } from "node:http";
import type { Duplex } from "node:stream";

const GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

export interface ConexionWs {
  enviar(texto: string): void;
  cerrar(): void;
}

export function aceptarWs(
  req: IncomingMessage,
  socket: Duplex,
  alRecibir: (texto: string, c: ConexionWs) => void,
): ConexionWs | null {
  const clave = req.headers["sec-websocket-key"];
  if (typeof clave !== "string") {
    socket.destroy();
    return null;
  }
  const acepta = createHash("sha1").update(clave + GUID).digest("base64");
  socket.write(
    "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
      `Sec-WebSocket-Accept: ${acepta}\r\n\r\n`,
  );
  let abierta = true;
  const c: ConexionWs = {
    enviar(texto) {
      if (!abierta) return;
      const datos = Buffer.from(texto, "utf8");
      const cab = datos.length < 126
        ? Buffer.from([0x81, datos.length])
        : Buffer.from([0x81, 126, datos.length >> 8, datos.length & 0xff]);
      socket.write(Buffer.concat([cab, datos]));
    },
    cerrar() {
      if (!abierta) return;
      abierta = false;
      socket.end(Buffer.from([0x88, 0]));
    },
  };
  let resto = Buffer.alloc(0);
  socket.on("data", (trozo: Buffer) => {
    resto = Buffer.concat([resto, trozo]);
    while (resto.length >= 2) {
      const op = resto[0] & 0x0f;
      let largo = resto[1] & 0x7f;
      let pos = 2;
      if (largo === 126) {
        if (resto.length < 4) return;
        largo = resto.readUInt16BE(2);
        pos = 4;
      } else if (largo === 127) {
        c.cerrar();
        return;
      }
      const conMascara = (resto[1] & 0x80) !== 0;
      const fin = pos + (conMascara ? 4 : 0) + largo;
      if (resto.length < fin) return;
      const mascara = conMascara ? resto.subarray(pos, pos + 4) : null;
      const carga = Buffer.from(resto.subarray(fin - largo, fin));
      if (mascara) for (let i = 0; i < carga.length; i++) carga[i] ^= mascara[i % 4];
      resto = resto.subarray(fin);
      if (op === 0x8) return c.cerrar();
      if (op === 0x1) alRecibir(carga.toString("utf8"), c);
    }
  });
  socket.on("close", () => (abierta = false));
  socket.on("error", () => (abierta = false));
  return c;
}
