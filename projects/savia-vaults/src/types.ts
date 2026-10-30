// Core types for SaviaVaults

export interface VaultConfig {
  name: string;
  path: string;
  allowedExtensions: string[];
  deniedPaths: string[];
  maxDepth: number;
  maxFileSize: number;
  schemaDir?: string;
  /** SE-420: nivel de la cúpula; con él, las notas de nivel superior no se sirven. Sin él (CLI local), todo. */
  confidentiality?: string;
}

export interface Frontmatter {
  title?: string;
  tags?: string[];
  created?: string;
  modified?: string;
  [key: string]: unknown;
}

export interface Note {
  path: string;
  name: string;
  frontmatter: Frontmatter;
  tags: string[];
  content: string;
  created: string;
  modified: string;
}

export interface SearchQuery {
  query: string;
  maxResults?: number;
  pathPrefix?: string;
  /** SE-330: enriquecer con score del grafo (context enrichment). */
  enrich?: boolean;
  /** SE-485 R5: incluir deprecated/superseded/archived y vencidos (def. `DEFAULT_INCLUDE_STALE`). */
  includeStale?: boolean;
  /** SE-485 R5: estados excluidos cuando `includeStale` es falso (def. los de RAG). */
  excludeStatuses?: string[];
}

export interface SearchResult {
  path: string;
  score: number;
  snippet: string;
  tags: string[];
  /** SE-485 R4: solo si la consulta lleva un identificador con forma de código. */
  exactMatch?: boolean;
  warnings?: string[];
}

export interface VaultStats {
  name: string;
  noteCount: number;
  totalSize: number;
  commitCount?: number;
  /** SE-420: notas fuera de nivel (ocultas); solo el número. */
  outOfLevel?: number;
  /** SE-481: notas en cuarentena (clasificación explícita no interpretable); solo el número. */
  quarantined?: number;
}

export interface CommitEntry {
  hash: string;
  date: string;
  message: string;
}

export interface Receipt {
  vault: string;
  path: string;
  contentHash: string;
  signature: string;
  timestamp: string;
}
