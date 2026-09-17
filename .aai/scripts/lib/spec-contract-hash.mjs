// spec-contract-hash.mjs — the amendment-anchor hash (SPEC-DRAFT
// spec-mutation-gate-for-tests D10). ONE module, imported by BOTH
// spec-freeze.mjs (the writer, which stamps `frozen_sha256` at freeze) and
// spec-amend.mjs (the reader, which recomputes it at `list --strict`) — the
// same D1 rule mutation-record.mjs already applies to the mutation schema.
//
// WHAT IS HASHED, AND WHY (D10)
//   Not the whole file: a `status: implementing` -> `done` close flip, or a
//   routine Test Plan Status/AC Evidence write during a TDD cycle, is the
//   ride's OWN bookkeeping, not an amendment — hashing the file would fire
//   the gate on every ordinary cycle. And not `specContentHash` in
//   docs-model.mjs either: that hash INCLUDES every AC status and EXCLUDES
//   every Description cell and all prose (measurement 15 in the spec) — the
//   exact inverse of what an amendment incident (SPEC-0171, CHANGE-0181)
//   actually rewrote. This hash is taken over a normalized CONTRACT
//   PROJECTION instead:
//     - the frontmatter block is removed entirely (so `status`, `number`,
//       `links.pr` and `frozen_sha256` itself never enter the hash — no
//       self-reference, and the close flip is not an amendment);
//     - in `## Acceptance Criteria Status`, the Status, Evidence, Review-By
//       and Notes cells are blanked (the ride's own bookkeeping);
//     - in `## Test Plan`, the Status cell is blanked (same reason);
//     - every other cell and every prose section is kept VERBATIM;
//     - trailing whitespace and trailing newlines are normalized.
//   That projection is exactly the set of bytes an amendment changes.
//
// Node stdlib only (docs/TECHNOLOGY.md).

import crypto from 'node:crypto';
import { normalizeNewlines, splitRawTableCells } from './docs-model.mjs';

export const CONTRACT_HASH_VERSION = 'v1';
export const FROZEN_HASH_FIELD = 'frozen_sha256';

// Section headings this module blanks columns inside. Matched loosely
// ("Acceptance Criteria" with an optional " Status" suffix) so a lean L1 AC
// table (heading `## Acceptance Criteria`, no `Status` suffix) is still
// covered — the blanked column NAMES are what matter, and a lean table
// simply has none of "evidence"/"review-by"/"notes" to blank.
// The heading line must be EXACTLY "## Acceptance Criteria" or "## Acceptance
// Criteria Status" (only trailing whitespace tolerated) — never `\b[^\n]*`,
// which would also swallow "## Acceptance Criteria Mapping" (a real, distinct
// heading every spec in this corpus carries) into the same section.
const AC_SECTION_RE = /(?:^|\n)(##\s+Acceptance Criteria(?:\s+Status)?[ \t]*\n)([\s\S]+?)(?=\n##\s|\n*$)/i;
const TEST_PLAN_SECTION_RE = /(?:^|\n)(##\s+Test Plan\b[^\n]*\n)([\s\S]+?)(?=\n##\s|\n*$)/i;

const AC_BLANK_COLUMNS = new Set(['status', 'evidence', 'review-by', 'notes']);
const TEST_PLAN_BLANK_COLUMNS = new Set(['status']);

// A markdown table separator row: `|---|:---:|---|` (dashes/colons/space
// only between the pipes). Left alone — it carries no per-row content.
const SEPARATOR_ROW_RE = /^\|?\s*:?-+:?\s*(\|\s*:?-+:?\s*)*\|?\s*$/;

// blankTableSection(sectionBody, blankNames) -> sectionBody with every data
// row's named columns replaced by a single blank cell. The header row is
// kept VERBATIM (its text is structural — column identity — not per-ride
// bookkeeping); only rows AFTER the header/separator are blanked.
//
// Remediation round 7 (Codex P1, PR #384): a literal `|` DOES appear inside
// a Test Plan Mutation cell in this repository — an escaped `\|` in a sed
// mutation expression like `s/if \(exemptN > 0 \|\| unstampedN > 0\) \{/…`
// (SPEC-0181's own TEST-511 row) — so a plain `split('|')` shifted that
// row's columns, and a routine Status flip on it changed the CONTRACT hash
// (an undisclosed-amendment false positive, since Status is supposed to be
// blanked bookkeeping). Cell boundaries are now split on UNESCAPED pipes
// only, via `splitRawTableCells` (lib/docs-model.mjs) — the SAME function
// `splitTableCells` (the Test Plan reader) builds on, reused directly here
// rather than a second hand-rolled splitter, so this module and the reader
// can never disagree about where a cell ends.
function blankTableSection(sectionBody, blankNames) {
  const lines = sectionBody.split('\n');
  let headerCols = null; // trimmed lower-case header cell names, in order
  const out = lines.map((line) => {
    if (!line.trim().startsWith('|')) return line;
    if (headerCols === null) {
      // First table line is the header.
      const cells = splitRawTableCells(line);
      headerCols = cells.slice(1, cells.length - 1).map((c) => c.trim().toLowerCase());
      return line;
    }
    if (SEPARATOR_ROW_RE.test(line.trim())) return line;
    const cells = splitRawTableCells(line);
    const idxs = [];
    headerCols.forEach((h, i) => { if (blankNames.has(h)) idxs.push(i + 1); });
    if (idxs.length === 0) return line;
    for (const idx of idxs) {
      if (idx > 0 && idx < cells.length - 1) cells[idx] = ' ';
    }
    return cells.join('|');
  });
  return out.join('\n');
}

// projectContract(content) -> the normalized CONTRACT PROJECTION text (D10).
// Pure and deterministic: same input, same output, every time — the whole
// point of an anchor that must survive a rebase and a squash merge.
export function projectContract(content) {
  let norm = normalizeNewlines(String(content ?? ''));

  // 1. Frontmatter block removed entirely.
  const fm = norm.match(/^---\n[\s\S]*?\n---\n?/);
  if (fm) norm = norm.slice(fm[0].length);

  // 2. AC table bookkeeping cells blanked.
  norm = norm.replace(AC_SECTION_RE, (whole, heading, body) => heading + blankTableSection(body, AC_BLANK_COLUMNS));

  // 3. Test Plan Status cell blanked.
  norm = norm.replace(TEST_PLAN_SECTION_RE, (whole, heading, body) => heading + blankTableSection(body, TEST_PLAN_BLANK_COLUMNS));

  // 4. Trailing whitespace and trailing newlines normalized.
  norm = norm.split('\n').map((l) => l.replace(/[ \t]+$/, '')).join('\n');
  norm = norm.replace(/\n+$/, '\n');
  if (!norm.endsWith('\n')) norm += '\n';

  return norm;
}

// contractHash(content) -> sha256 hex of the contract projection.
export function contractHash(content) {
  return crypto.createHash('sha256').update(projectContract(content), 'utf8').digest('hex');
}
