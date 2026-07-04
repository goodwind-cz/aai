// state-core.mjs — shared structural STATE.yaml primitives (SPEC-0012 D4).
//
// ONE definition of "duplicate top-level key" (and of line normalization /
// top-level block location) shared by BOTH the validator (check-state.mjs) and
// the transactional writer (state.mjs), so the writer can never produce what the
// validator rejects through a forked re-implementation. Extracted verbatim from
// check-state.mjs (ISSUE-0004 / SPEC-0010 Group B) — a PURE TEXT SCAN, no YAML
// library (the repo ships none; docs/TECHNOLOGY.md).

// A top-level key line: `name:` at column 0 (no leading whitespace). Excludes
// comments (`# ...`), document markers (`---`), and blank lines. Block-scalar and
// nested content is indented, so it never matches at column 0. This is also why
// a commented schema-header line (e.g. `#   updated_at_utc: ...`) can NEVER be
// mistaken for the real field (the CHANGE-0005 timestamp-regex mishap class).
export const TOP_KEY_RE = /^([A-Za-z_][\w-]*):/;

export function topLevelKeyCounts(lines) {
  const counts = new Map();
  for (const raw of lines) {
    if (!raw || raw.startsWith('#') || raw.startsWith('---')) continue;
    const m = raw.match(TOP_KEY_RE);
    if (!m) continue;
    counts.set(m[1], (counts.get(m[1]) ?? 0) + 1);
  }
  return counts;
}

export function duplicateKeys(lines) {
  const dups = [];
  for (const [key, n] of topLevelKeyCounts(lines)) {
    if (n > 1) dups.push({ key, count: n });
  }
  return dups;
}

// Normalize raw file content into lines (CRLF/lone-CR -> LF) plus the
// trailing-newline convention, so counts and re-emission are exact
// (same discipline as check-state.mjs main()).
export function splitLines(content) {
  const trailingNewline = content.endsWith('\n');
  const lines = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n').split('\n');
  if (trailingNewline && lines.length && lines[lines.length - 1] === '') lines.pop();
  return { lines, trailingNewline };
}

export function joinLines(lines, trailingNewline) {
  return lines.join('\n') + (trailingNewline ? '\n' : '');
}

// A block-scalar header value: `|` or `>` plus optional chomping/indentation
// indicators in either order (`|-`, `|+`, `>-`, `>+`, `|2`, `|2-`, ...),
// optionally followed by a trailing comment. Indented content under one of
// these is scalar text, never structure.
export const BLOCK_SCALAR_REST_RE = /^[|>][0-9+-]{0,2}(?:\s+#.*)?$/;

// Detect the "child lines under an inline-valued header" corruption: a
// top-level `key: <inline value>` line whose first following content line is
// MORE-indented structure (a `k:` mapping field or a `- ` sequence item). YAML
// rejects that shape ("mapping values are not allowed here") — a mapping value
// would be given twice. Shared so the transactional writer refuses to produce
// what this validator flags (SPEC-0012 SEAM-1; review-20260704T093742Z W2).
export function inlineChildConflicts(lines) {
  const conflicts = [];
  for (let i = 0; i < lines.length; i += 1) {
    const m = lines[i].match(TOP_KEY_RE);
    if (!m) continue;
    const rest = lines[i].slice(m[0].length).trim();
    if (rest === '' || rest.startsWith('#') || BLOCK_SCALAR_REST_RE.test(rest)) continue;
    for (let j = i + 1; j < lines.length; j += 1) {
      const l = lines[j];
      if (TOP_KEY_RE.test(l) || l.startsWith('---')) break;   // next top-level key ends the scan
      if (l.trim() === '' || l.trim().startsWith('#')) continue;
      if (/^ +(- |-$|[^\s]+:(\s|$))/.test(l)) conflicts.push({ key: m[1], line: i + 1 });
      break;   // only the first content line under the header decides
    }
  }
  return conflicts;
}

// Return the [start, end) line-index ranges of every top-level block whose
// header line matches `headerRe` (e.g. /^metrics:\s*$/). The block runs to the
// next top-level key; comment/marker lines never terminate a block.
export function topBlockRanges(lines, headerRe) {
  const ranges = [];
  for (let i = 0; i < lines.length; i += 1) {
    if (!headerRe.test(lines[i])) continue;
    let end = lines.length;
    for (let j = i + 1; j < lines.length; j += 1) {
      const l = lines[j];
      if (l.startsWith('#') || l.startsWith('---')) continue;
      if (TOP_KEY_RE.test(l)) { end = j; break; }
    }
    ranges.push([i, end]);
  }
  return ranges;
}
