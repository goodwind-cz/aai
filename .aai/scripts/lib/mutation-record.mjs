// mutation-record.mjs — the v1 mutation-record schema (SPEC-DRAFT
// spec-mutation-gate-for-tests D1, D2). ONE module, imported by BOTH the
// writer (mutation-run.mjs) and the reader (mutation-gate.mjs, and
// mutation-run.mjs --replay reads back its own prior writes) so the record
// shape can never drift between a producer and a consumer that each hand-
// rolled their own idea of the header (the exact defect SPEC-0180 D13/S5
// closed for the liveness slot).
//
// SHAPE (D2): a fixed `key: value` header, one field per line, then a `---`
// separator line, then the captured tail of the run:
//
//   mutation_record: v1
//   spec_id: <spec frontmatter id>
//   test_id: TEST-<n>
//   suite: <repo-relative suite path>
//   selector: <suite's own test_* function name>
//   target: <repo-relative path of the mutated file>
//   mutation: <mutation expression, e.g. "sed:s/OLD/NEW/">
//   base_commit: <40 hex>
//   tree_hash: <hex of the SOURCE working tree>
//   run_at_utc: <ISO 8601 seconds>
//   rc: <suite run's exit code>
//   verdict: RED | STAYED GREEN | INCONCLUSIVE
//   first_fail: <one line naming why, or a placeholder>
//   ---
//   <tail of the run>
//
// Node stdlib only (docs/TECHNOLOGY.md).

export const MUTATION_RECORD_VERSION = 'v1';

// Order matters only for the WRITTEN header's readability; parseRecord()
// accepts any order and is keyed by name, never by position (SPEC-0180's own
// lesson about positional record parsing, reapplied here on day one).
export const HEADER_FIELDS = [
  'mutation_record',
  'spec_id',
  'test_id',
  'suite',
  'selector',
  'target',
  'mutation',
  'base_commit',
  'tree_hash',
  'run_at_utc',
  'rc',
  'verdict',
  'first_fail',
];

export const VERDICTS = new Set(['RED', 'STAYED GREEN', 'INCONCLUSIVE']);

const SEPARATOR = '\n---\n';

// formatRecord(fields, tailText) -> the full record TEXT (header + separator
// + tail), ready to write to disk. `fields` must carry every key in
// HEADER_FIELDS except `mutation_record` (added here, pinned to v1 — a
// caller cannot accidentally write a different version). `tailText` is the
// already-truncated tail (see lastLines below); it is written verbatim.
export function formatRecord(fields, tailText) {
  const lines = [`mutation_record: ${MUTATION_RECORD_VERSION}`];
  for (const key of HEADER_FIELDS) {
    if (key === 'mutation_record') continue;
    const v = fields[key];
    if (v === undefined || v === null || String(v).includes('\n')) {
      throw new Error(`mutation-record: field "${key}" must be a single-line, non-empty value (got ${JSON.stringify(v)})`);
    }
    lines.push(`${key}: ${v}`);
  }
  const tail = tailText == null ? '' : String(tailText);
  const body = tail.endsWith('\n') ? tail.slice(0, -1) : tail;
  return `${lines.join('\n')}${SEPARATOR}${body}\n`;
}

// parseRecord(text) -> { ok: true, fields, tail } | { ok: false, error }.
// Never throws — a malformed record is DATA a caller must handle (a gate
// reading a hand-corrupted or foreign file), never an exception a caller
// must remember to catch.
export function parseRecord(text) {
  const norm = String(text).replace(/\r\n/g, '\n');
  const sepIdx = norm.indexOf(SEPARATOR);
  if (sepIdx === -1) return { ok: false, error: 'missing "---" header/tail separator' };
  const header = norm.slice(0, sepIdx);
  const tail = norm.slice(sepIdx + SEPARATOR.length);
  const fields = {};
  for (const line of header.split('\n')) {
    if (!line.trim()) continue;
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*):[ \t]?(.*)$/);
    if (!m) return { ok: false, error: `malformed header line: ${JSON.stringify(line)}` };
    fields[m[1]] = m[2];
  }
  if (fields.mutation_record !== MUTATION_RECORD_VERSION) {
    return { ok: false, error: `unsupported or missing mutation_record version (got ${JSON.stringify(fields.mutation_record ?? null)}, want "${MUTATION_RECORD_VERSION}")` };
  }
  for (const key of HEADER_FIELDS) {
    if (!(key in fields)) return { ok: false, error: `missing required field: ${key}` };
  }
  if (!VERDICTS.has(fields.verdict)) {
    return { ok: false, error: `invalid verdict: ${JSON.stringify(fields.verdict)}` };
  }
  return { ok: true, fields, tail };
}

// lastLines(text, n) -> the last n lines of text, joined by "\n". Used to
// build the record's tail from a full run's captured output (D2: "the last
// 200 lines of the run").
export function lastLines(text, n) {
  const lines = String(text).replace(/\r\n/g, '\n').split('\n');
  return lines.slice(Math.max(0, lines.length - n)).join('\n');
}

// recordFileName / rotatedFileName — the D2 naming rule, kept in one place so
// the runner and any future reader agree on the shape without re-deriving it.
export function recordFileName(testId) {
  return `mutation-${testId}.txt`;
}

export function rotatedFileName(testId, runAtUtc) {
  return `mutation-${testId}.${runAtUtc}.txt`;
}

// isRotatedFileName(name, testId) -> true for a rotated sibling of testId's
// record (mutation-<testId>.<timestamp>.txt), false for the live record name
// itself or for an unrelated file. Used by callers (mutation-run.mjs
// --replay) that must enumerate only LIVE records in an evidence directory.
export function isRotatedFileName(name, testId) {
  const esc = testId.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(`^mutation-${esc}\\.[^.]+\\.txt$`).test(name);
}
