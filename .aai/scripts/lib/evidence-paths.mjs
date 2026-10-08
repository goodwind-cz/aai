// lib/evidence-paths.mjs — close-time evidence-path extraction (CHANGE-0131 /
// docs/specs/SPEC-0118-spec-evidence-path-gate.md). Pure functions only: the
// six-rule D2 grammar that decides whether a token inside an AC table's
// Evidence cell is a candidate repo-relative path, plus the doc-level and
// unresolved-filter wrappers close-work-item.mjs consults to choose
// warn-vs-refuse. Node stdlib only (docs/TECHNOLOGY.md). The extraction half
// invokes no git; the D6 rescue half (bottom of file) runs read-only
// `git check-ignore` to decide what may be copied.
//
// GRAMMAR (D2, measured before it was written — see the spec's D3 for the
// live-corpus evidence base: 752 tokens extracted, 0 false positives over
// 718 cells). A token is a candidate path only when ALL of these hold, IN
// THIS ORDER, after stripping surrounding markdown punctuation:
//   1. still contains at least one '/'
//   2. contains no ellipsis ('...' or the single-character U+2026 '…') — the
//      SPEC-0114 abbreviation `docs/ai/tdd/red-...test_011/012/014...log` is
//      root-anchored and charset-clean; without this rule it would be
//      extracted and the gate would refuse a legitimate close.
//   3. every remaining character is in [A-Za-z0-9._/-] — subsumes globs,
//      brace expansions, line-number suffixes (file.mjs:591), URLs and
//      backtick-glued joins in one stroke.
//   4. does not begin with '/' (never an absolute path or a slash command)
//   5. no '/'-delimited segment is exactly '..'
//   6. its FIRST segment names an existing DIRECTORY at the repo root — the
//      rule that kills the 142-strong no-root-dir prose family
//      (TEST-001/002, A/B, RFC-0030/RFC-0032/RFC-0034, ...).
//
// D6 — AC rows come ONLY from the shared readers (parseAcTable with a
// parseLeanAcTable fallback, imported from lib/docs-model.mjs). No local
// heading regex here (S2, grep-contract pinned by TEST-037): a fourth
// implementation of "what the AC table is" is exactly the drift CHANGE-0009
// D8 already removed once.

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { parseAcTable, parseLeanAcTable } from './docs-model.mjs';

const LEADING_RE = /^[`'"(\[{]/;
const TRAILING_RE = /[`'"),.;:\]}]$/;
const CHARSET_RE = /^[A-Za-z0-9._/-]+$/;

// stripEdgePunct(tok) -> `tok` with leading/trailing markdown punctuation
// repeatedly peeled (rule 1's "after stripping" clause) — a single pass
// would miss a stacked case like "log)." (trailing paren THEN period).
function stripEdgePunct(tok) {
  let s = tok;
  let changed = true;
  while (changed && s.length > 0) {
    changed = false;
    if (LEADING_RE.test(s)) { s = s.slice(1); changed = true; }
    if (s.length > 0 && TRAILING_RE.test(s)) { s = s.slice(0, -1); changed = true; }
  }
  return s;
}

// isExistingRootDir(root, segment) -> true when `segment` names an existing
// DIRECTORY directly under `root` (rule 6). This is a MODULE-LEVEL cache
// keyed on the (root, segment) pair — not "memoized per call site" (every
// call site sharing this module shares the same cache) — D2's "the
// root-directory probe is memoized per call site so a 9-row table costs a
// handful of statSync calls, not one per token" describes the effect (one
// statSync per distinct segment, not per token), not the cache's scope.
const ROOT_DIR_CACHE = new Map();
function isExistingRootDir(root, segment) {
  const key = `${root}\u0000${segment}`;
  if (ROOT_DIR_CACHE.has(key)) return ROOT_DIR_CACHE.get(key);
  let result = false;
  try {
    result = fs.statSync(path.join(root, segment)).isDirectory();
  } catch {
    result = false;
  }
  ROOT_DIR_CACHE.set(key, result);
  return result;
}

// extractEvidencePaths(cell, root) -> deduped candidate path tokens, in
// first-appearance order, from one Evidence cell string. `root` is the repo
// root the rule-6 directory probe resolves against. Never throws; a non-
// string cell yields [].
export function extractEvidencePaths(cell, root) {
  if (typeof cell !== 'string' || cell === '') return [];
  const seen = new Set();
  const out = [];
  for (const raw of cell.split(/\s+/)) {
    if (!raw) continue;
    const tok = stripEdgePunct(raw);
    if (!tok || !tok.includes('/')) continue;                    // rule 1
    if (tok.includes('...') || tok.includes('…')) continue;  // rule 2
    if (!CHARSET_RE.test(tok)) continue;                          // rule 3
    if (tok.startsWith('/')) continue;                            // rule 4
    const segments = tok.split('/');
    if (segments.some((s) => s === '..')) continue;               // rule 5
    const first = segments[0];
    if (!first || !isExistingRootDir(root, first)) continue;      // rule 6
    if (seen.has(tok)) continue;
    seen.add(tok);
    out.push(tok);
  }
  return out;
}

// evidenceCitations(content, root) -> [{ acId, token }] for every candidate
// path across every AC row's Evidence cell (D5/D6). AC rows come from
// parseAcTable, falling back to parseLeanAcTable when the canonical
// Review-By-gated table is absent (mirrors spec-lint's own dual path).
// Returns [] when there is no AC table or no Evidence column — a row
// missing the key (row['Evidence'] === undefined) contributes nothing.
export function evidenceCitations(content, root) {
  const ac = parseAcTable(content);
  const rows = ac.hasGate ? ac.rows : parseLeanAcTable(content).rows;
  const out = [];
  for (const row of rows) {
    const cell = row['Evidence'];
    if (cell === undefined) continue;
    const acId = row['Spec-AC'];
    for (const token of extractEvidencePaths(cell, root)) {
      out.push({ acId, token });
    }
  }
  return out;
}

// unresolvedCitations(content, root) -> evidenceCitations(content, root)
// filtered to tokens that do NOT resolve from `root` (D4 — existence, not
// git-tracking: fs.existsSync, and a directory counts as resolvable).
export function unresolvedCitations(content, root) {
  return evidenceCitations(content, root).filter(
    ({ token }) => !fs.existsSync(path.join(root, token))
  );
}

// --- D6 evidence rescue (post-validation-pushes-reuse-test-results Spec-AC-10) --
//
// Runtime evidence (docs/ai/reports, docs/ai/tdd, docs/ai/validation) is
// gitignored. A close run from a linked worktree resolves citations against the
// main checkout, so ignored evidence that exists ONLY in the worktree would warn
// even though nothing is wrong with it. planEvidenceRescue names the tokens that
// can safely be copied into the main checkout; copyEvidenceRescue performs the
// copy. Neither stages, tracks or commits anything.

// safeTree(abs) -> true when `abs` is a regular file, or a directory containing
// only regular files and directories (no symlink anywhere beneath it).
function safeTree(abs) {
  let st;
  try { st = fs.lstatSync(abs); } catch { return false; }
  if (st.isSymbolicLink()) return false;
  if (st.isFile()) return true;
  if (!st.isDirectory()) return false;
  let names;
  try { names = fs.readdirSync(abs); } catch { return false; }
  return names.every((n) => safeTree(path.join(abs, n)));
}

// ignoredByRepoRules(tree, rel, isDir) -> true when git's repository rules
// (.gitignore files only: core.excludesFile emptied) ignore `rel` under `tree`,
// whether or not it exists there. A directory is probed through a child path so
// both `dir/**` and `dir/` rules match.
function ignoredByRepoRules(tree, rel, isDir) {
  const probe = isDir ? `${rel}/.rescue-probe` : rel;
  const r = spawnSync(
    'git',
    ['-c', 'core.excludesFile=', 'check-ignore', '-q', '--no-index', '--', probe],
    { cwd: tree, stdio: 'ignore' },
  );
  return r.status === 0;
}

// planEvidenceRescue(tokens, root, evidenceRoot) -> [{ token, from, to }] for
// every token that exists under `root` as a symlink-free file or directory, with
// nothing at the destination, and is ignored by repository rules in BOTH trees.
// Pure: no write. Deduped, first-appearance order.
export function planEvidenceRescue(tokens, root, evidenceRoot) {
  const out = [];
  const seen = new Set();
  let realRoot;
  try { realRoot = fs.realpathSync(root); } catch { return out; }
  for (const token of tokens) {
    if (seen.has(token)) continue;
    seen.add(token);
    const from = path.join(root, token);
    const to = path.join(evidenceRoot, token);
    let st;
    try { st = fs.lstatSync(from); } catch { continue; }
    if (st.isSymbolicLink()) continue;
    try {
      if (fs.realpathSync(from) !== path.join(realRoot, token)) continue;   // symlinked parent
    } catch { continue; }
    if (!safeTree(from)) continue;
    if (fs.existsSync(to)) continue;
    const isDir = st.isDirectory();
    if (!ignoredByRepoRules(root, token, isDir)) continue;
    if (!ignoredByRepoRules(evidenceRoot, token, isDir)) continue;
    out.push({ token, from, to });
  }
  return out;
}

// copyEvidenceRescue(plan) -> { copied: [entry], failed: [entry] }. No clobber:
// errorOnExist with force:false. A failure leaves the destination as it was.
export function copyEvidenceRescue(plan) {
  const copied = [];
  const failed = [];
  for (const entry of plan) {
    try {
      fs.mkdirSync(path.dirname(entry.to), { recursive: true });
      fs.cpSync(entry.from, entry.to, { recursive: true, errorOnExist: true, force: false });
      copied.push(entry);
    } catch {
      failed.push(entry);
    }
  }
  return { copied, failed };
}
