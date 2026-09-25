// friction-spool.mjs — the ONE spool-line predicate RFC-0012 friction tooling
// shares (spec-friction-channel-sweep Spec-AC-11, PR #394 review F1).
//
// A spool line counts as an observation if it parses as JSON and is a plain
// object (not an array, not a scalar) — never merely "non-blank". Before this
// file existed, aai-feedback-triage.mjs's own readSpool() applied exactly
// this rule when it set `total_observations`, while aai-feedback-status.mjs's
// countObservations() counted every non-blank line instead. The two counts
// only ever agreed while the spool held zero malformed lines: one line left
// behind by a crashed or concurrent writer permanently pinned the status
// surface's `report_stale` to true, because its raw line count could never
// again equal the triage report's parseable-row count — defeating Spec-AC-11
// from the opposite direction of the "stale reads as current" defect it
// fixed. Both scripts now read the count through this one function.
import { readFileSync } from 'node:fs';

// readSpoolRows(path) -> parsed observation objects, one per line that parses
// as a JSON plain object; a blank line, a line that fails JSON.parse, or a
// line that parses to a non-object (array/scalar) is silently skipped —
// tolerating a partial/corrupt line rather than failing the whole read. A
// missing spool file reads as an empty spool (0 rows), not an error.
export function readSpoolRows(path) {
  let text;
  try { text = readFileSync(path, 'utf8'); } catch { return []; }
  const rows = [];
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    try {
      const obj = JSON.parse(line);
      if (obj && typeof obj === 'object' && !Array.isArray(obj)) rows.push(obj);
    } catch { /* tolerate a partial/corrupt line */ }
  }
  return rows;
}

// countSpoolRows(path) -> readSpoolRows(path).length. The shared count both
// the triage report's `total_observations` and the status surface's
// `observations` must report, so the two can never drift apart again.
export function countSpoolRows(path) {
  return readSpoolRows(path).length;
}
