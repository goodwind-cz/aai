#!/usr/bin/env node
/**
 * check-base-ref-pins.mjs — the bare-`main` base-ref guard
 * (follow-up fu-bare-main-baseref-sweep, ISSUE-0038).
 *
 * THE DEFECT CLASS
 * A GitHub Actions `pull_request` checkout is a DETACHED HEAD with only the
 * remote-tracking refs fetched: `origin/main` resolves, a bare `main` does NOT.
 * A shell line like
 *
 *     (cd "$PROJECT_ROOT" && git diff --name-only main...HEAD 2>/dev/null)
 *
 * therefore produces NOTHING on CI, the `2>/dev/null` swallows the error, and
 * every guard hanging off that output silently stops guarding — it reports PASS
 * on an empty read. This had happened FOUR times in this repository before this
 * check existed (TEST-024 in test-aai-release.sh, the follow-ups suite,
 * test-aai-spec-lint.sh, then test-aai-deslop.sh TEST-027/028). Every single
 * time it was caught by a human reading a diff. Never by a check.
 *
 * WHAT THIS GUARD DOES
 * Two independent instruments over the same scan, because they answer different
 * questions:
 *
 *   1. HARD GATE (never baselined, never waived). An occurrence that resolves a
 *      ref against the REAL repository (`$PROJECT_ROOT`) and has no
 *      `origin/main` attempt in the 8 lines above it is UNSAFE and fails,
 *      naming file:line. This is the exact shape all four prior incidents had.
 *   2. RATCHET (an explicitly recorded baseline). Every occurrence of the shape
 *      — including the legitimate ones — is counted per file against
 *      tests/skills/lib/base-ref-pin-baseline.tsv. A NEW file or a RISEN count
 *      fails. A SHRINK is reported but NEVER lowers the bar on its own; the bar
 *      is re-recorded by hand so the lowering is visible. Same discipline as
 *      tests/skills/lib/pipe-grep-q-ratchet.sh, and for the same reason.
 *
 * A repo-wide rewrite of every legitimate fixture-local `main` is out of scope,
 * so the ratchet baseline is the honest instrument for those: it is RECORDED,
 * not silently capped, and every row is a file this scanner measured.
 *
 * NEVER A NO-OP. The failure mode being fixed is a guard that degrades to PASS
 * when it cannot read its source of truth, so this one fails CLOSED on every
 * such condition: no files matched, zero occurrences found in a corpus known to
 * carry some, an unreadable file, a missing or empty baseline. Silence is never
 * reported as cleanliness.
 *
 * USAGE
 *   node .aai/scripts/check-base-ref-pins.mjs                  # gate (exit 1 on failure)
 *   node .aai/scripts/check-base-ref-pins.mjs --json           # machine-readable report
 *   node .aai/scripts/check-base-ref-pins.mjs --record         # (re)write the baseline
 *   node .aai/scripts/check-base-ref-pins.mjs --root <dir> --baseline <tsv>
 *
 * EXIT CODES
 *   0  clean: no UNSAFE occurrence and no ratchet RISE/NEW
 *   1  a finding (UNSAFE, RISE, NEW) or a degraded scan
 *   2  usage error
 */

import fs from 'node:fs';
import path from 'node:path';

const SCAN_DIRS = ['tests/skills', '.aai/scripts'];
const BASELINE_REL = 'tests/skills/lib/base-ref-pin-baseline.tsv';

// A ref-RESOLVING git verb (the verbs that read history) whose argument is a
// bare `main`. Deliberately NOT matched: branch construction and movement
// (`git init -b main`, `git checkout -b x main`, `git branch -M main`,
// `git worktree add ... main`, `git push ... main`) — a fixture builder naming
// the branch it is creating is not a base-ref pin.
//   - `[^/A-Za-z0-9_$-]` before `main` excludes `origin/main`, `refs/heads/main`,
//     `chore/legacy-main` and the shell variable `$main`.
//   - `[^A-Za-z0-9/_-]|$` after it keeps `main..HEAD` / `main...HEAD` /
//     `main:path` (all real pins) while excluding `mainline`, `main-thing`.
const VERBS = [
  'rev-parse', 'merge-base', 'diff', 'log', 'show', 'rev-list',
  'symbolic-ref', 'describe', 'cherry', 'for-each-ref', 'ls-tree',
  'cat-file', 'merge-tree',
].join('|');
const OCCURRENCE_RE = new RegExp(
  `(^|[^A-Za-z0-9_-])git\\s[^|;]*(${VERBS})[^|;]*[^/A-Za-z0-9_$-]main([^A-Za-z0-9/_-]|$)`,
);

// How far back to look for the `origin/main` attempt that makes a real-repo pin
// a deliberate, ordered fallback rather than a silent one. The three legitimate
// `base_ref()` helpers in this repository all put it 2-3 lines above.
const GUARD_WINDOW = 8;
// How far back a `cd "$dir" && {` block opener can be and still scope the line.
const SCOPE_WINDOW = 4;

const REAL_REPO_VAR = /^(PROJECT_ROOT|GITHUB_WORKSPACE)$/;

function fail(msg) {
  process.stderr.write(`check-base-ref-pins: ${msg}\n`);
  process.exit(2);
}

function parseArgs(argv) {
  const args = { record: false, json: false, root: process.cwd(), baseline: null };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (a === '--record') args.record = true;
    else if (a === '--json') args.json = true;
    else if (a === '--root') { args.root = argv[++i]; if (!args.root) fail('--root needs a directory'); }
    else if (a === '--baseline') { args.baseline = argv[++i]; if (!args.baseline) fail('--baseline needs a path'); }
    else if (a === '--help' || a === '-h') { process.stdout.write(HELP); process.exit(0); }
    else fail(`unknown argument: ${a}`);
  }
  return args;
}

const HELP = `usage: check-base-ref-pins.mjs [--record] [--json] [--root <dir>] [--baseline <tsv>]

Fails when a git command resolves a ref against a bare 'main' in the real
repository without an 'origin/main' attempt above it (UNSAFE), or when the
per-file occurrence count rises above the recorded baseline.
`;

/** Every *.sh file under the scan dirs that exist in <root>, sorted. */
export function scanFiles(root) {
  const out = [];
  for (const rel of SCAN_DIRS) {
    const dir = path.join(root, rel);
    let names;
    try {
      names = fs.readdirSync(dir);
    } catch {
      continue; // a tree without this directory is a valid tree, not a finding
    }
    for (const n of names.sort()) {
      if (!n.endsWith('.sh')) continue;
      const p = path.join(dir, n);
      let st;
      try { st = fs.statSync(p); } catch { continue; }
      if (st.isFile()) out.push(p);
    }
  }
  return out;
}

/**
 * The variable a git invocation is scoped to on this line, or null when the
 * line does not scope it. Tolerates backslash-escaped quotes (a suite writing
 * a fixture suite: `git -C \"\$R\" rev-parse ...`).
 */
function scopeVarOnLine(line) {
  // `[\\"']*` and not a single optional escape: a suite that WRITES a fixture
  // suite carries doubly-escaped quotes (`git -C \"\$R\" rev-parse ...`).
  const dashC = line.match(/git\s+(?:[^|;]*?\s)?-C\s+[\\"']*\$\{?([A-Za-z_][A-Za-z0-9_]*)/);
  if (dashC) return dashC[1];
  const cd = line.match(/\bcd\s+[\\"']*\$\{?([A-Za-z_][A-Za-z0-9_]*)/);
  if (cd) return cd[1];
  return null;
}

/** The variable an unclosed `cd "$dir" && {` block opener scopes, or null. */
function scopeVarFromOpener(line) {
  const m = line.match(/\bcd\s+[\\"']*\$\{?([A-Za-z_][A-Za-z0-9_]*)[^&]*&&\s*\{\s*$/);
  return m ? m[1] : null;
}

/**
 * classify(lines, i) -> 'UNSAFE' | 'GUARDED' | 'FIXTURE' | 'STRING'
 *
 * STRING   the `git` token is inside a quoted argument handed to something else
 *          (a hook-adapter payload, a heredoc body) — not an invocation here.
 * FIXTURE  scoped to a directory variable that is not the real repository.
 * GUARDED  real-repo scoped, with an `origin/main` attempt at or above it.
 * UNSAFE   real-repo scoped, with none. THIS is the CI-fatal shape.
 */
export function classify(lines, i) {
  const line = lines[i];

  const gitAt = line.search(new RegExp(`(^|[^A-Za-z0-9_-])git\\s`));
  const quoteIdx = gitAt === -1 ? -1 : line.indexOf('git', gitAt) - 1;
  if (quoteIdx >= 0 && (line[quoteIdx] === '"' || line[quoteIdx] === "'")) return 'STRING';

  let scope = scopeVarOnLine(line);
  if (scope === null) {
    for (let j = i - 1; j >= 0 && j >= i - SCOPE_WINDOW; j -= 1) {
      const v = scopeVarFromOpener(lines[j]);
      if (v !== null) { scope = v; break; }
    }
  }
  if (scope !== null && !REAL_REPO_VAR.test(scope)) return 'FIXTURE';

  for (let j = i; j >= 0 && j >= i - GUARD_WINDOW; j -= 1) {
    if (lines[j].includes('origin/main')) return 'GUARDED';
  }
  return 'UNSAFE';
}

/** All occurrences in <root>. Throws on an unreadable file — never skips it. */
export function occurrences(root) {
  const files = scanFiles(root);
  const out = [];
  for (const file of files) {
    let text;
    try {
      text = fs.readFileSync(file, 'utf8');
    } catch (e) {
      // An unreadable file is a DEGRADED scan, not a clean one.
      throw new Error(`unreadable file ${path.relative(root, file)}: ${e.message}`);
    }
    const lines = text.split('\n');
    for (let i = 0; i < lines.length; i += 1) {
      const line = lines[i];
      if (/^\s*#/.test(line)) continue; // a comment cannot resolve a ref
      if (!OCCURRENCE_RE.test(line)) continue;
      out.push({
        file: path.relative(root, file),
        base: path.basename(file),
        line: i + 1,
        cls: classify(lines, i),
        text: line.trim(),
      });
    }
  }
  return { files, out };
}

/** Per-file occurrence counts, sorted by file name. */
export function countsOf(occ) {
  const m = new Map();
  for (const o of occ) m.set(o.base, (m.get(o.base) || 0) + 1);
  return [...m.entries()].sort((a, b) => (a[0] < b[0] ? -1 : 1));
}

export function readBaseline(file) {
  const text = fs.readFileSync(file, 'utf8');
  const rows = [];
  for (const raw of text.split('\n')) {
    const l = raw.trim();
    if (!l || l.startsWith('#')) continue;
    const [n, name] = l.split('\t');
    if (!name || !/^\d+$/.test(n)) throw new Error(`malformed baseline row: ${raw}`);
    rows.push([name, Number(n)]);
  }
  return rows;
}

/** RISE / NEW (failing) and SHRINK / GONE (reported only). */
export function compare(baseRows, nowRows) {
  const base = new Map(baseRows);
  const now = new Map(nowRows);
  const verdicts = [];
  for (const [name, n] of now) {
    const b = base.get(name) || 0;
    if (b === 0) verdicts.push({ kind: 'NEW', name, base: 0, now: n });
    else if (n > b) verdicts.push({ kind: 'RISE', name, base: b, now: n });
    else if (n < b) verdicts.push({ kind: 'SHRINK', name, base: b, now: n });
  }
  for (const [name, b] of base) {
    if (!now.has(name)) verdicts.push({ kind: 'GONE', name, base: b, now: 0 });
  }
  return verdicts;
}

export function renderBaseline(rows) {
  return [
    '# tests/skills/lib/base-ref-pin-baseline.tsv',
    '#',
    '# GENERATED, never hand-edited:',
    '#   node .aai/scripts/check-base-ref-pins.mjs --record',
    '#',
    '# One `<occurrences>\\t<file>` row per scanned shell file that resolves a git',
    '# ref against a bare `main`. The count may FALL, never RISE: a rise (or a file',
    '# not listed here) fails tests/skills/test-aai-hygiene-pack.sh and names the',
    '# file. A SHRINK keeps its recorded number until someone re-records on',
    '# purpose, so that lowering the bar is a visible act.',
    '#',
    '# Being listed here is NOT a waiver of the hard gate: an occurrence scoped to',
    '# the real repository with no `origin/main` attempt above it fails whether or',
    '# not this file mentions it.',
    '#',
    ...rows.map(([name, n]) => `${n}\t${name}`),
    '',
  ].join('\n');
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  const root = path.resolve(args.root);
  const baselineFile = args.baseline ? path.resolve(args.baseline) : path.join(root, BASELINE_REL);

  let files;
  let occ;
  try {
    ({ files, out: occ } = occurrences(root));
  } catch (e) {
    process.stderr.write(`DEGRADED SCAN (failing closed): ${e.message}\n`);
    process.exit(1);
  }

  const rows = countsOf(occ);
  const total = occ.length;

  if (args.record) {
    fs.writeFileSync(baselineFile, renderBaseline(rows), 'utf8');
    process.stdout.write(
      `recorded ${total} occurrence(s) across ${rows.length} file(s) from ${root} -> ${baselineFile}\n`,
    );
    return;
  }

  const problems = [];
  const notes = [];

  // ---- anti-no-op preconditions -------------------------------------------
  // Each of these is a state in which the scan CANNOT contradict anything. A
  // guard that reports PASS here is the very defect this file exists to catch.
  if (files.length === 0) {
    problems.push(
      `no shell file was scanned under ${root} (looked in: ${SCAN_DIRS.join(', ')}) — `
      + 'an empty corpus can never contradict a baseline, so this fails rather than passing',
    );
  } else if (total === 0) {
    problems.push(
      `the scanner found 0 occurrence(s) across ${files.length} scanned file(s) — `
      + 'the corpus is known to carry some, so a zero here is a broken scanner, not a clean tree',
    );
  }

  let baseRows = null;
  try {
    baseRows = readBaseline(baselineFile);
  } catch (e) {
    problems.push(
      `the baseline ${path.relative(root, baselineFile)} is missing or unreadable (${e.message}) — `
      + 'record it: node .aai/scripts/check-base-ref-pins.mjs --record',
    );
  }
  if (baseRows && baseRows.length === 0) {
    problems.push(
      `the baseline ${path.relative(root, baselineFile)} has no data rows — `
      + 'record it: node .aai/scripts/check-base-ref-pins.mjs --record',
    );
  }

  // ---- 1. the hard gate ---------------------------------------------------
  const unsafe = occ.filter(o => o.cls === 'UNSAFE');
  for (const o of unsafe) {
    problems.push(
      `UNSAFE base-ref pin ${o.file}:${o.line} — resolves a ref against a bare 'main' in the real `
      + 'repository. On a GitHub `pull_request` checkout (detached HEAD, only remote-tracking refs '
      + 'fetched) there is no local `main`, so this silently reads nothing and the guard above it '
      + 'degrades to PASS. Resolve `origin/main` first, fall back to `main`, and FAIL CLOSED when '
      + `neither resolves.\n      ${o.text}`,
    );
  }

  // ---- 2. the ratchet -----------------------------------------------------
  if (baseRows && baseRows.length > 0) {
    for (const v of compare(baseRows, rows)) {
      if (v.kind === 'NEW' || v.kind === 'RISE') {
        problems.push(
          `${v.kind} ${v.name} ${v.base} -> ${v.now} — a new bare-'main' ref pin. If it is a `
          + 'deliberate fixture-local `main` or an ordered origin/main-first fallback, re-record the '
          + 'baseline on purpose: node .aai/scripts/check-base-ref-pins.mjs --record',
        );
      } else {
        notes.push(`${v.kind} ${v.name} ${v.base} -> ${v.now} (the bar is not lowered automatically)`);
      }
    }
  }

  const byClass = { UNSAFE: 0, GUARDED: 0, FIXTURE: 0, STRING: 0 };
  for (const o of occ) byClass[o.cls] += 1;

  if (args.json) {
    process.stdout.write(`${JSON.stringify({
      root, scanned_files: files.length, total, by_class: byClass,
      occurrences: occ, counts: rows, notes, problems,
    }, null, 2)}\n`);
  } else {
    process.stdout.write(
      `base-ref pins: ${total} occurrence(s) in ${rows.length} of ${files.length} scanned file(s) `
      + `(UNSAFE ${byClass.UNSAFE}, GUARDED ${byClass.GUARDED}, FIXTURE ${byClass.FIXTURE}, `
      + `STRING ${byClass.STRING})\n`,
    );
    for (const n of notes) process.stdout.write(`NOTE: ${n}\n`);
    for (const p of problems) process.stderr.write(`FAIL: ${p}\n`);
  }

  process.exit(problems.length > 0 ? 1 : 0);
}

// Importable as a library (the hygiene-pack arm drives the classifier
// directly); only the direct invocation runs the gate.
if (process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname)) {
  main();
}
