// registry.mjs — per-harness parser registry (SPEC-DRAFT-spec-live-status-dashboard,
// Spec-AC-02 / Spec-AC-04). Each entry declares: id, roots(env), discover(roots),
// parse(file, ctx), accumulation, project(record), and optionally
// rateLimits(records). The generator knows nothing else about any harness —
// adding a harness means adding one module + one row below, nothing else in
// generate-live-status.mjs changes.
//
// registerParsers(entries) validates every entry against the contract and
// throws a NAMED error the moment a required field is missing or an
// accumulation mode is unrecognized — a malformed entry is refused outright,
// never silently producing partial totals (TEST-006).

import claudeCode from './claude-code.mjs';
import codex from './codex.mjs';
import geminiCli from './gemini-cli.mjs';

const REQUIRED_FIELDS = ['id', 'roots', 'discover', 'parse', 'accumulation', 'project'];
const VALID_ACCUMULATION = new Set(['event_sum_dedup', 'session_cumulative_last', 'none']);

export function validateEntry(entry) {
  if (!entry || typeof entry !== 'object') {
    throw new Error('live-parsers registry: entry must be an object');
  }
  for (const field of REQUIRED_FIELDS) {
    if (!(field in entry) || entry[field] === undefined) {
      throw new Error(`live-parsers registry: entry "${entry.id ?? '?'}" missing required field "${field}"`);
    }
  }
  if (!VALID_ACCUMULATION.has(entry.accumulation)) {
    throw new Error(`live-parsers registry: entry "${entry.id}" has invalid accumulation "${entry.accumulation}" (expected one of ${[...VALID_ACCUMULATION].join(', ')})`);
  }
  return entry;
}

export function registerParsers(entries) {
  return entries.map(validateEntry);
}

// The three shipped parsers (Spec-AC-04). Validated eagerly so a broken
// built-in entry fails at import time, not at first use.
export const PARSERS = registerParsers([claudeCode, codex, geminiCli]);

export default PARSERS;
