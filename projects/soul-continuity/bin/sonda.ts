// Sonda del lanzador: si este Node ejecuta TypeScript, imprime la marca y su versión.
const marca: string = "soul-ts-ok";
process.stdout.write(`${marca} ${process.version}`);
