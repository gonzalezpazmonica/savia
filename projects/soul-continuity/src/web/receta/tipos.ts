// Formato de receta del adaptador `web` (SE-490). Una receta es configuración
// declarativa del operador: nada de código por sitio. Todo lo que no está en
// sus listas cerradas se aborta.

/** Patrón de ruta relativo al origen: `/tareas?pagina=*`. `*` casa 1+ caracteres
 *  sin cruzar `/ ? & = #`. Sin `*` es coincidencia exacta de ruta y consulta. */
export type PatronUrl = string;

/** Dónde declara el cliente la operación de un POST de lectura. */
export type FuenteOperacion =
  | { cabecera: string }
  | { cuerpo_json: string; graphql?: boolean };

export interface OperacionesPost {
  url: PatronUrl;
  operacion: FuenteOperacion;
  /** Lista cerrada de operaciones de lectura: se dejan pasar. */
  lectura: string[];
  /** Escrituras que el cliente lanza solo (marcar leído…): se abortan sin desactivar. */
  escritura_conocida: string[];
}

export interface AccionNavegacion {
  id: string;
  /** Selector del elemento que se pulsa (paginar, expandir, pestaña). */
  selector: string;
  /** URLs que esta acción puede provocar: subconjunto de `urls`. */
  urls: PatronUrl[];
  max_repeticiones: number;
}

export type Valor =
  | { attr: string; tipo?: TipoCampo }
  | { sel: string; attr?: string; tipo?: TipoCampo };
export type TipoCampo = "texto" | "lista" | "fecha" | "booleano";

export interface Extraccion {
  /** Selector de cada elemento de la vista de lista. */
  elemento: string;
  /** Identificador estable del elemento. */
  id: Valor;
  campos: Record<string, Valor>;
}

export type Condicion =
  | { todas: Condicion[] }
  | { alguna: Condicion[] }
  | { campo: string; op: "igual" | "distinto" | "contiene" | "no_contiene"; valor: string }
  | { campo: string; op: "existe" | "vacio" | "verdadero" | "falso" };

/** `experimental`: plantilla sin validar contra tráfico real; no se ejecuta sin
 *  un recibo local de validación (activacion.ts). `estable`: validada. */
export type EstadoReceta = "experimental" | "estable";

export interface Receta {
  formato: "soul-receta-web/1";
  id: string;
  sitio: string;
  estado: EstadoReceta;
  /** Notas para el operador (qué está sin verificar). No las lee el cortafuegos. */
  notas?: string[];
  /** Origen exacto (esquema, host y puerto). Las variables `{x}` las completa
   *  `cargarReceta` (el puerto en el banco, el inquilino en las plantillas). */
  origen: string;
  /** JavaScript de la página: `false` salvo clientes que lo necesitan (SPA). */
  javascript: boolean;
  /** Lista cerrada de patrones de URL visitables. Relativos: navegación y
   *  subrecursos del origen. Absolutos (otro origen): solo subrecursos. */
  urls: PatronUrl[];
  /** POST de renovación de sesión permitidos (lista por sitio). */
  renovacion_sesion: PatronUrl[];
  post_lectura: OperacionesPost[];
  websocket: { urls: PatronUrl[]; mantenimiento: string[] };
  /** Páginas de entrada, en orden. */
  paginas: PatronUrl[];
  acciones: AccionNavegacion[];
  extraccion: Extraccion;
  /** Clasificación determinista; `{yo}` es la identidad del operador. */
  preguntas: Partial<Record<"q1" | "q2" | "q4", Condicion>>;
  /** Patrones relativos de login u orígenes enteros de login federado (`https://login.example`). */
  sesion: { login: PatronUrl[] };
  humo: { pagina: PatronUrl; minimo: number; campos_obligatorios: string[] };
}
