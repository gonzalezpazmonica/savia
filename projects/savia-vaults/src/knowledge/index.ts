export { extractWikiLinks, validateWikiLinks, resolveBacklinks, resolveWikiTarget, buildEntityIndex, computeWikiLinkHealth } from './wikilink-validator.js';
export {
  validateOkfFrontmatter,
  convertWikiLinksToMarkdown,
  convertMarkdownLinksToWikiLinks,
  inferOkfType,
  serializeOkfNote,
  OKF_REQUIRED_FIELDS,
  OKF_OPTIONAL_FIELDS,
  OKF_RESERVED_FILENAMES,
} from './okf.js';
export { checkOkfConformance } from './okf-conformance.js';
export { exportOkfBundle } from './okf-export.js';
export { importOkfBundle } from './okf-import.js';
export {
  createDecisionRecord,
  validateDecision,
} from './decision.js';
export type {
  DecisionRecord,
  DecisionState,
  ProvenanceRef,
} from './decision.js';
export { detectConflicts, resolveConflict } from './conflicts.js';
export type { Conflict, ConflictSeverity, ConflictStatus } from './conflicts.js';
export { promote, getActiveState } from './decision-state.js';
export type { DecisionStateLog, StateChange } from './decision-state.js';
